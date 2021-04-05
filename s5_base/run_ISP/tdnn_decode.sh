#!/usr/bin/env bash

# 7n is a kind of factorized TDNN, with skip connections.
# See: http://www.danielpovey.com/files/2018_interspeech_tdnnf.pdf

set -e

# configs for 'chain'
stage=0
speed_perturb=true


affix=

# End configuration section.
echo "$0 $*"  # Print the command line for logging

# LMs
decoding_lang=/home/derik/work/samromur-asr/s5_subwords/data_ISP/isl_lm/lang_6g
rescoring_lang=/home/derik/work/samromur-asr/s5_subwords/data_ISP/isl_lm/lang_8g
langdir=

# I'm making these into varibles so that I can better control the folders that are created
exp=exp_ISP

. ./path.sh
. ./cmd.sh
. ./utils/parse_options.sh || exit 1;


if [ ! $# = 2 ]; then
  echo "Decode step"
  exit 1;
fi

inputdata=$1
testdatadir=$2

printf "\n Decode set afstað $(date)\n\n"


( ! cmp $langdir/words.txt $decoding_lang/words.txt || \
! cmp $decoding_lang/words.txt $rescoring_lang/words.txt ) && \
echo "$0: Warning: vocabularies may be incompatible."

suffix=
$speed_perturb && suffix=_sp
dir=$exp/chain/tdnn${affix}${suffix}

if [ $stage -le 1 ]; then
  # Note: it might appear that this $lang directory is mismatched, and it is as
  # far as the 'topo' is concerned, but this script doesn't read the 'topo' from
  # the lang directory.
  echo "Making the graph for $dir"
  utils/slurm.pl --mem 40G $dir/log/mkgraph.log \
                utils/mkgraph.sh --self-loop-scale \
                1.0 \
                $decoding_lang \
                $dir \
                $dir/graph
fi

graph_dir=$dir/graph


if [ $stage -le 2 ]; then
  rm $dir/.error 2>/dev/null || true

  if [[ $inputdata == *"isl"* ]]; then
    for decode_set in sm_dev sm_test althingi_dev althingi_test; do
      echo "Decoding $decode_set"
      (
       steps/nnet3/decode.sh --acwt 1.0 \
                              --cmd "$decode_cmd --time 0-06 --config conf/slurm-decode.conf" \
                              --post-decode-acwt 10.0 \
                              --nj 30 \
                              --skip_diagnostics true \
                              --online-ivector-dir $exp/nnet3/ivectors_${decode_set} \
                              $graph_dir \
                              $testdatadir/${decode_set}_hires \
                              $dir/decode_${decode_set}_6g || exit 1;
        
        steps/lmrescore_const_arpa.sh --cmd "$decode_cmd --config conf/slurm-decode.conf" \
                                     $decoding_lang \
                                     $rescoring_lang \
                                     $testdatadir/${decode_set}_hires \
                                     $dir/decode_${decode_set}_6g \
                                     $dir/decode_${decode_set}_8g_rescored|| exit 1;
      ) || touch $dir/.error 
    done
    
  elif [[ $inputdata == *"libri"* ]]; then
      for decode_set in dev_clean test_clean; do
      (
        num_jobs=$(cat $testdatadir/${decode_set}_hires/utt2spk|cut -d' ' -f2|sort -u|wc -l)
        steps/nnet3/decode.sh --acwt 1.0 \
                              --cmd "$decode_cmd --time 0-06" \
                              --post-decode-acwt 10.0 \
                              --skip_diagnostics true \
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
echo "Done!"
exit 0;