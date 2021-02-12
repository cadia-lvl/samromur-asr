#!/usr/bin/env bash

# run_tdnn_7k.sh is like run_tdnn_7h.sh but batchnorm components instead of renorm

# local/chain/compare_wer_general.sh tdnn_7h_sp/ tdnn_7k_sp/
# System                tdnn_7h_sp/ tdnn_7k_sp/
# WER on train_dev(tg)      13.99     13.98
# WER on train_dev(fg)      12.82     12.66
# WER on eval2000(tg)        16.8      16.6
# WER on eval2000(fg)        15.3      15.0
# Final train prob         -0.087    -0.087
# Final valid prob         -0.107    -0.103
# Final train prob (xent)        -1.252    -1.223
# Final valid prob (xent)       -1.3105   -1.2945

set -e

# configs for 'chain'
affix=
stage=12
train_stage=-10
get_egs_stage=-10
speed_perturb=true
dir=exp/chain/tdnn_7k  # Note: _sp will get added to this if $speed_perturb == true.
decode_iter=
decode_nj=50

# training options
num_epochs=4
initial_effective_lrate=0.001
final_effective_lrate=0.0001
max_param_change=2.0
final_layer_normalize_target=0.5
num_jobs_initial=3
num_jobs_final=16
minibatch_size=128
frames_per_eg=150
remove_egs=true
common_egs_dir=
xent_regularize=0.1

# GMM to use for alignments
gmm=tri4

test_online_decoding=false  # if true, it will run the last decoding stage.
generate_plots=false

# End configuration section.
echo "$0 $@"  # Print the command line for logging

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

# LMs
decoding_lang=data/lang_3g
rescoring_lang=data/lang_4g
#zerogramLM=$data/lang_zg
langdir=data/lang

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
if [ "$speed_perturb" == "true" ]; then
    suffix=_sp
fi

dir=${dir}${affix:+_$affix}$suffix
train_set=train$suffix
ali_dir=exp/${gmm}_ali$suffix
treedir=exp/chain/${gmm}_tree$suffix
lang=data/lang_chain


# if we are using the speed-perturbed data we need to generate
# alignments for it.
local/nnet3/run_ivector_common.sh --stage $stage \
--speed-perturb $speed_perturb \
--generate-alignments $speed_perturb || exit 1;


if [ $stage -le 9 ]; then
    # Get the alignments as lattices (gives the LF-MMI training more freedom).
    # use the same num-jobs as the alignments
    nj=$(cat exp/${gmm}_ali$suffix/num_jobs) || exit 1;
    steps/align_fmllr_lats.sh --nj $nj --cmd "$train_cmd" data/$train_set \
    data/lang exp/${gmm} exp/${gmm}_lats$suffix
    rm exp/${gmm}_lats$suffix/fsts.*.gz # save space
fi


if [ $stage -le 10 ]; then
    # Create a version of the lang/ directory that has one state per phone in the
    # topo file. [note, it really has two states.. the first one is only repeated
    # once, the second one has zero or more repeats.]
    rm -rf $lang
    cp -r data/lang $lang
    silphonelist=$(cat $lang/phones/silence.csl) || exit 1;
    nonsilphonelist=$(cat $lang/phones/nonsilence.csl) || exit 1;
    # Use our special topology... note that later on may have to tune this
    # topology.
    steps/nnet3/chain/gen_topo.py $nonsilphonelist $silphonelist >$lang/topo
fi

if [ $stage -le 11 ]; then
    # Build a tree using our new topology. This is the critically different
    # step compared with other recipes.
    steps/nnet3/chain/build_tree.sh --frame-subsampling-factor 3 \
    --context-opts "--context-width=2 --central-position=1" \
    --cmd "$train_cmd" 7000 data/$train_set $lang $ali_dir $treedir
fi

if [ $stage -le 12 ]; then
    echo "$0: creating neural net configs using the xconfig parser";
    
    num_targets=$(tree-info $treedir/tree |grep num-pdfs|awk '{print $2}')
    learning_rate_factor=$(echo "print (0.5/$xent_regularize)" | python)
    
    mkdir -p $dir/configs
  cat <<EOF > $dir/configs/network.xconfig
  input dim=100 name=ivector
  input dim=40 name=input

  # please note that it is important to have input layer with the name=input
  # as the layer immediately preceding the fixed-affine-layer to enable
  # the use of short notation for the descriptor
  fixed-affine-layer name=lda input=Append(-1,0,1,ReplaceIndex(ivector, t, 0)) affine-transform-file=$dir/configs/lda.mat

  # the first splicing is moved before the lda layer, so no splicing here
  relu-batchnorm-layer name=tdnn1 dim=625
  relu-batchnorm-layer name=tdnn2 input=Append(-1,0,1) dim=625
  relu-batchnorm-layer name=tdnn3 input=Append(-1,0,1) dim=625
  relu-batchnorm-layer name=tdnn4 input=Append(-3,0,3) dim=625
  relu-batchnorm-layer name=tdnn5 input=Append(-3,0,3) dim=625
  relu-batchnorm-layer name=tdnn6 input=Append(-3,0,3) dim=625
  relu-batchnorm-layer name=tdnn7 input=Append(-3,0,3) dim=625

  ## adding the layers for chain branch
  relu-batchnorm-layer name=prefinal-chain input=tdnn7 dim=625 target-rms=0.5
  output-layer name=output include-log-softmax=false dim=$num_targets max-change=1.5

  # adding the layers for xent branch
  # This block prints the configs for a separate output that will be
  # trained with a cross-entropy objective in the 'chain' models... this
  # has the effect of regularizing the hidden parts of the model.  we use
  # 0.5 / args.xent_regularize as the learning rate factor- the factor of
  # 0.5 / args.xent_regularize is suitable as it means the xent
  # final-layer learns at a rate independent of the regularization
  # constant; and the 0.5 was tuned so as to make the relative progress
  # similar in the xent and regular final layers.
  relu-batchnorm-layer name=prefinal-xent input=tdnn7 dim=625 target-rms=0.5
  output-layer name=output-xent dim=$num_targets learning-rate-factor=$learning_rate_factor max-change=1.5

EOF
    steps/nnet3/xconfig_to_configs.py --xconfig-file $dir/configs/network.xconfig --config-dir $dir/configs/
fi

if [ $stage -le 13 ]; then
    if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $dir/egs/storage ]; then
        utils/create_split_dir.pl \
        /export/b0{5,6,7,8}/$USER/kaldi-data/egs/swbd-$(date +'%m_%d_%H_%M')/s5c/$dir/egs/storage $dir/egs/storage
    fi
    
    steps/nnet3/chain/train.py --stage $train_stage \
    --cmd "$decode_cmd" \
    --feat.online-ivector-dir exp/nnet3/ivectors_${train_set} \
    --feat.cmvn-opts "--norm-means=false --norm-vars=false" \
    --chain.xent-regularize $xent_regularize \
    --chain.leaky-hmm-coefficient 0.1 \
    --chain.l2-regularize 0.00005 \
    --chain.apply-deriv-weights false \
    --chain.lm-opts="--num-extra-lm-states=2000" \
    --egs.dir "$common_egs_dir" \
    --egs.stage $get_egs_stage \
    --egs.opts "--frames-overlap-per-eg 0" \
    --egs.chunk-width $frames_per_eg \
    --trainer.num-chunk-per-minibatch $minibatch_size \
    --trainer.frames-per-iter 1500000 \
    --trainer.num-epochs $num_epochs \
    --trainer.optimization.num-jobs-initial $num_jobs_initial \
    --trainer.optimization.num-jobs-final $num_jobs_final \
    --trainer.optimization.initial-effective-lrate $initial_effective_lrate \
    --trainer.optimization.final-effective-lrate $final_effective_lrate \
    --trainer.max-param-change $max_param_change \
    --cleanup.remove-egs $remove_egs \
    --feat-dir data/${train_set}_hires \
    --tree-dir $treedir \
    --lat-dir exp/${gmm}_lats$suffix \
    --dir $dir  || exit 1;
    
fi

if [ $stage -le 14 ]; then
    # Note: it might appear that this $lang directory is mismatched, and it is as
    # far as the 'topo' is concerned, but this script doesn't read the 'topo' from
    # the lang directory.
    echo "Make a small 3-gram graph"
    utils/slurm.pl --mem 8G $dir/log/mkgraph.log utils/mkgraph.sh --self-loop-scale 1.0 $decoding_lang $dir $dir/graph_3g
fi

graph_dir=$dir/graph_3g
iter_opts=
if [ ! -z $decode_iter ]; then
    iter_opts=" --iter $decode_iter "
fi

if [ $stage -le 15 ]; then
    rm $dir/.error 2>/dev/null || true
    for decode_set in dev eval; do
        (
            num_jobs=$(cat $data/${decode_set}_hires/utt2spk|cut -d' ' -f2|sort -u|wc -l)
            steps/nnet3/decode.sh \
            --acwt 1.0 --post-decode-acwt 10.0 \
            --nj $num_jobs --cmd "$decode_cmd --time 0-06" $iter_opts \
            --online-ivector-dir $exp/nnet3/ivectors_${decode_set} \
            $graph_dir $data/${decode_set}_hires \
            $dir/decode_${decode_set}${decode_iter:+_$decode_iter}_3g || exit 1;
            steps/lmrescore_const_arpa.sh \
            --cmd "$decode_cmd" \
            $decoding_lang $rescoring_lang $data/${decode_set}_hires \
            $dir/decode_${decode_set}${decode_iter:+_$decode_iter}_{3g,4g} || exit 1;
        ) || touch $dir/.error &
    done
    wait
    if [ -f $dir/.error ]; then
        echo "$0: something went wrong in decoding"
        exit 1
    fi
fi

if $test_online_decoding && [ $stage -le 16 ]; then
    # note: if the features change (e.g. you add pitch features), you will have to
    # change the options of the following command line.
    steps/online/nnet3/prepare_online_decoding.sh \
    --mfcc-config conf/mfcc_hires.conf \
    $lang exp/nnet3/extractor $dir ${dir}_online
    
    rm $dir/.error 2>/dev/null || true
    for decode_set in train_dev eval2000; do
        (
            # note: we just give it "$decode_set" as it only uses the wav.scp, the
            # feature type does not matter.
            
            steps/online/nnet3/decode.sh --nj $decode_nj --cmd "$decode_cmd" \
            --acwt 1.0 --post-decode-acwt 10.0 \
            $graph_dir data/${decode_set}_hires \
            ${dir}_online/decode_${decode_set}${decode_iter:+_$decode_iter}_sw1_tg || exit 1;
            if $has_fisher; then
                steps/lmrescore_const_arpa.sh --cmd "$decode_cmd" \
                data/lang_sw1_{tg,fsh_fg} data/${decode_set}_hires \
                ${dir}_online/decode_${decode_set}${decode_iter:+_$decode_iter}_sw1_{tg,fsh_fg} || exit 1;
            fi
        ) || touch $dir/.error &
    done
    wait
    if [ -f $dir/.error ]; then
        echo "$0: something went wrong in decoding"
        exit 1
    fi
fi

if $generate_plots && [ $stage -le 17 ]; then
    echo "Generating plots and compiling a latex report on the training"
    if [[ $(hostname -f) == terra.hir.is ]]; then
        conda activate thenv || error 11 $LINENO "Can't activate thenv";
        steps/nnet3/report/generate_plots.py \
        --is-chain true $dir $dir/report_tdnn${affix}$suffix
        conda deactivate
    else
        steps/nnet3/report/generate_plots.py \
        --is-chain true $dir $dir/report_tdnn${affix}$suffix
    fi
fi

exit 0;
