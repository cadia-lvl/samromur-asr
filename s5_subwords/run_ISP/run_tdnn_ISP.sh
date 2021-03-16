#!/usr/bin/env bash

# 7n is a kind of factorized TDNN, with skip connections.
# See: http://www.danielpovey.com/files/2018_interspeech_tdnnf.pdf

set -e

# configs for 'chain'
stage=0
align_stage=0
train_stage=-10
get_egs_stage=-10
speed_perturb=true

# GMM to use for alignments
gmm=tri3b
generate_ali_from_lats=false

affix=


# training options
frames_per_eg=150,110,100
remove_egs=true
common_egs_dir=
xent_regularize=0.1

# End configuration section.
echo "$0 $*"  # Print the command line for logging

# LMs
decoding_lang=/home/derik/work/samromur-asr/s5_subwords/data_ISP/isl_lm/lang_6g
rescoring_lang=/home/derik/work/samromur-asr/s5_subwords/data_ISP/isl_lm/lang_8g
langdir=$data/${code}_lang 

# I'm making these into varibles so that I can better control the folders that are created
data=data_ISP
exp=exp_ISP

. ./path.sh
. ./cmd.sh
. ./utils/parse_options.sh || exit 1;


if [ ! $# = 2 ]; then
  echo "This script trains a factorized time delay deep neural network"
  echo "and tests the new model on a development set"
  echo ""
  echo "Usage: $0 [options] <input-training-data> <test-data-dir>"
  echo " e.g.: $0 data/train_okt2017_500k_cleaned data"
  echo ""
  echo "Options:"
  echo "    --speed-perturb <bool>           # apply speed perturbations, default: true"
  echo "    --generate-ali-from-lats <bool>  # ali.*.gz is generated in lats dir, default: false"
  echo "    --affix <affix>                  # idendifier for the model, e.g. _1b"
  echo "    --decode-iter <iter>         # iteration of model to test"
  echo "    --generate-plots <bool>      # generate a report on the training"
  echo "    --calculate-bias <bool>      # estimate the bias by decoding a subset of the training set"
  echo "    --zerogram-decoding <bool>   # check the effect of the LM on the decoding results"
  exit 1;
fi

inputdata=$1
testdatadir=$2


( ! cmp $langdir/words.txt $decoding_lang/words.txt || \
! cmp $decoding_lang/words.txt $rescoring_lang/words.txt ) && \
echo "$0: Warning: vocabularies may be incompatible."

if ! cuda-compiled; then
  cat <<EOF && exit 1
This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA
If you want to use GPUs (and have them), go to src/, and configure and make on a machine
where "nvcc" is installed.
EOF
fi

# The iVector-extraction and feature-dumping parts are the same as the standard
# nnet3 setup, and you can skip them by setting "--stage 8" if you have already
# run those things.

suffix=
$speed_perturb && suffix=_sp
dir=$exp/chain/tdnn${affix}${suffix}

train_set=$(basename $inputdata)$suffix
ali_dir=$exp/${gmm}_ali_${train_set}
treedir=$exp/chain/${gmm}_tree$suffix 
lang=$data/lang_chain

# if we are using the speed-perturbed data we need to generate
# alignments for it.
run_ISP/run_ivector_common_ISP.sh --stage $stage \
                                  --speed-perturb $speed_perturb \
                                  --generate-alignments $speed_perturb \
                                  --data $data --exp $exp \
                                  $inputdata $testdatadir $langdir $gmm || exit 1;

# See if regular alignments already exist
if [ -f ${ali_dir}/num_jobs ]; then
  n_alijobs=$(cat ${ali_dir}/num_jobs)
else
  n_alijobs=`cat $data/${train_set}/utt2spk|cut -d' ' -f2|sort -u|wc -l`
  generate_ali_from_lats=true
  ali_dir=$exp/${gmm}_lats$suffix
fi

if [ $stage -le 9 ]; then
  # Get the alignments as lattices (gives the CTC training more freedom).
  # use the same num-jobs as the alignments
  #nj=$(cat ${ali_dir}/num_jobs) || exit 1;
  steps/align_fmllr_lats.sh --nj $n_alijobs \
                            --stage $align_stage \
                            --cmd "$train_cmd --time 2-00" \
                            --generate-ali-from-lats \
                            $generate_ali_from_lats \
                            $data/$train_set \
                            $langdir \
                            $exp/${gmm} \
                            $exp/${gmm}_lats$suffix
  
  rm $exp/${gmm}_lats$suffix/fsts.*.gz # save space
fi

if [ $stage -le 10 ]; then
  # Create a version of the lang/ directory that has one state per phone in the
  # topo file. [note, it really has two states.. the first one is only repeated
  # once, the second one has zero or more repeats.]
  rm -rf $lang
  cp -r $langdir $lang
  silphonelist=$(cat $lang/phones/silence.csl) || exit 1;
  nonsilphonelist=$(cat $lang/phones/nonsilence.csl) || exit 1;
  # Use our special topology... note that later on may have to tune this
  # topology.
  steps/nnet3/chain/gen_topo.py $nonsilphonelist $silphonelist >$lang/topo
fi

if [ $stage -le 11 ]; then
  # Build a tree using our new topology.
  steps/nnet3/chain/build_tree.sh --frame-subsampling-factor 3 \
                                  --context-opts "--context-width=2 --central-position=1" \
                                  --cmd "$train_cmd --time 2-00" \
                                  11000 \
                                  $data/$train_set \
                                  $lang \
                                  $ali_dir \
                                  $treedir
fi


if [ $stage -le 12 ]; then
  echo "$0: creating neural net configs using the xconfig parser";
  
  num_targets=$(tree-info $treedir/tree |grep num-pdfs|awk '{print $2}')
  learning_rate_factor=$(echo "print(0.5/$xent_regularize)" | python3)
  opts="l2-regularize=0.002"
  linear_opts="orthonormal-constraint=1.0"
  output_opts="l2-regularize=0.0005 bottleneck-dim=256"
  
  mkdir -p $dir/configs
  
  cat <<EOF > $dir/configs/network.xconfig
  input dim=100 name=ivector
  input dim=40 name=input

  # please note that it is important to have input layer with the name=input
  # as the layer immediately preceding the fixed-affine-layer to enable
  # the use of short notation for the descriptor
  fixed-affine-layer name=lda input=Append(-1,0,1,ReplaceIndex(ivector, t, 0)) affine-transform-file=$dir/configs/lda.mat

  # the first splicing is moved before the lda layer, so no splicing here
  relu-batchnorm-layer name=tdnn1 $opts dim=1280
  linear-component name=tdnn2l dim=256 $linear_opts input=Append(-1,0)
  relu-batchnorm-layer name=tdnn2 $opts input=Append(0,1) dim=1280
  linear-component name=tdnn3l dim=256 $linear_opts
  relu-batchnorm-layer name=tdnn3 $opts dim=1280
  linear-component name=tdnn4l dim=256 $linear_opts input=Append(-1,0)
  relu-batchnorm-layer name=tdnn4 $opts input=Append(0,1) dim=1280
  linear-component name=tdnn5l dim=256 $linear_opts
  relu-batchnorm-layer name=tdnn5 $opts dim=1280 input=Append(tdnn5l, tdnn3l)
  linear-component name=tdnn6l dim=256 $linear_opts input=Append(-3,0)
  relu-batchnorm-layer name=tdnn6 $opts input=Append(0,3) dim=1280
  linear-component name=tdnn7l dim=256 $linear_opts input=Append(-3,0)
  relu-batchnorm-layer name=tdnn7 $opts input=Append(0,3,tdnn6l,tdnn4l,tdnn2l) dim=1280
  linear-component name=tdnn8l dim=256 $linear_opts input=Append(-3,0)
  relu-batchnorm-layer name=tdnn8 $opts input=Append(0,3) dim=1280
  linear-component name=tdnn9l dim=256 $linear_opts input=Append(-3,0)
  relu-batchnorm-layer name=tdnn9 $opts input=Append(0,3,tdnn8l,tdnn6l,tdnn4l) dim=1280
  linear-component name=tdnn10l dim=256 $linear_opts input=Append(-3,0)
  relu-batchnorm-layer name=tdnn10 $opts input=Append(0,3) dim=1280
  linear-component name=tdnn11l dim=256 $linear_opts input=Append(-3,0)
  relu-batchnorm-layer name=tdnn11 $opts input=Append(0,3,tdnn10l,tdnn8l,tdnn6l) dim=1280
  linear-component name=prefinal-l dim=256 $linear_opts

  relu-batchnorm-layer name=prefinal-chain input=prefinal-l $opts dim=1280
  output-layer name=output include-log-softmax=false dim=$num_targets $output_opts

  relu-batchnorm-layer name=prefinal-xent input=prefinal-l $opts dim=1280
  output-layer name=output-xent dim=$num_targets learning-rate-factor=$learning_rate_factor $output_opts
EOF
  steps/nnet3/xconfig_to_configs.py --xconfig-file $dir/configs/network.xconfig --config-dir $dir/configs/

fi

  echo "Stoppa fyrir nnet3"
  exit 1


if [ $stage -le 13 ]; then
  
  steps/nnet3/chain/train.py  --stage $train_stage \
                              --cmd "$train_cmd --time 1-12" \
                              --feat.online-ivector-dir $exp/nnet3/ivectors_${train_set} \
                              --feat.cmvn-opts "--norm-means=false --norm-vars=false" \
                              --chain.xent-regularize $xent_regularize \
                              --chain.leaky-hmm-coefficient 0.1 \
                              --chain.l2-regularize 0.0 \
                              --chain.apply-deriv-weights false \
                              --chain.lm-opts="--num-extra-lm-states=2000" \
                              --egs.dir "$common_egs_dir" \
                              --egs.stage $get_egs_stage \
                              --egs.opts "--frames-overlap-per-eg 0" \
                              --egs.chunk-width $frames_per_eg \
                              --trainer.num-chunk-per-minibatch 128 \
                              --trainer.frames-per-iter 1500000 \
                              --trainer.num-epochs 6 \
                              --trainer.optimization.num-jobs-initial 3 \
                              --trainer.optimization.num-jobs-final 16 \
                              --trainer.optimization.initial-effective-lrate 0.001 \
                              --trainer.optimization.final-effective-lrate 0.0001 \
                              --trainer.max-param-change 2.0 \
                              --cleanup.remove-egs $remove_egs \
                              --feat-dir $data/${train_set}_hires \
                              --tree-dir $treedir \
                              --lat-dir $exp/${gmm}_lats$suffix \
                              --dir $dir  || exit 1;
  
fi


if [ $stage -le 14 ]; then
  # Note: it might appear that this $lang directory is mismatched, and it is as
  # far as the 'topo' is concerned, but this script doesn't read the 'topo' from
  # the lang directory.
  echo "Make the graph"
  utils/slurm.pl --mem 60G $dir/log/mkgraph.log utils/mkgraph.sh --self-loop-scale 1.0 $decoding_lang $dir $dir/graph
fi

graph_dir=$dir/graph


if [ $stage -le 15 ]; then
  rm $dir/.error 2>/dev/null || true

  echo $inputdata
  if [[ $inputdata == *"isl"* ]]; then
    for decode_set in sm_dev sm_test althingi_dev althingi_test; do
      (
        num_jobs=$(cat $testdatadir/${decode_set}_hires/utt2spk|cut -d' ' -f2|sort -u|wc -l)
        steps/nnet3/decode.sh --acwt 1.0 \
                              --cmd "$decode_cmd --time 0-06" $iter_opts \
                              --post-decode-acwt 10.0 \
                              --nj $num_jobs \
                              --online-ivector-dir $exp/nnet3/ivectors_${decode_set} \
                              $graph_dir \
                              $testdatadir/${decode_set}_hires \
                              $dir/decode_${decode_set}_6g || exit 1;
        

        steps/lmrescore_const_arpa.sh --cmd "$decode_cmd" \
                                      $decoding_lang \
                                      $rescoring_lang \
                                      $testdatadir/${decode_set}_hires \
                                      $dir/decode_${decode_set}_8g || exit 1;
      ) || touch $dir/.error 
    done

  elif [[ $inputdata == *"libri"* ]]; then
      for decode_set in dev_clean test_clean; do
      (
        num_jobs=$(cat $testdatadir/${decode_set}_hires/utt2spk|cut -d' ' -f2|sort -u|wc -l)
        steps/nnet3/decode.sh --acwt 1.0 \
                              --cmd "$decode_cmd --time 0-06" $iter_opts \
                              --post-decode-acwt 10.0 \
                              --nj $num_jobs \
                              --online-ivector-dir $exp/nnet3/ivectors_${decode_set} \
                              $graph_dir \
                              $testdatadir/${decode_set}_hires \
                              $dir/decode_${decode_set}_6g || exit 1;
        

        steps/lmrescore_const_arpa.sh --cmd "$decode_cmd" \
                                      $decoding_lang \
                                      $rescoring_lang \
                                      $testdatadir/${decode_set}_hires \
                                      $dir/decode_${decode_set}_6g \
                                      $dir/decode_${decode_set}_8g_rescored || exit 1;
      ) || touch $dir/.error 
      done
  fi 
  wait
  if [ -f $dir/.error ]; then
    echo "$0: something went wrong in decoding"
    exit 1
  fi
fi

exit 0;