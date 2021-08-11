#!/usr/bin/env bash

set -e

stage=0
speed_perturb=true

affix=
suffix=

# End configuration section.
echo "$0 $*"  # Print the command line for logging

# LMs
decoding_lang=
rescoring_lang=
langdir=

ivector_extractor=
exp=exp
tag=
boundary_marker=
n_jobs=30
sw_separator='+'
mfccdir=$exp/mfcc
log=logs


. ./path.sh
. ./cmd.sh
. ./utils/parse_options.sh || exit 1;


if [ ! $# = 1 ]; then
  echo "Error in decoding"
  exit 1;
fi

decode_data_dir=$1
data_set=$(basename $decode_data_dir)


( ! cmp $langdir/words.txt $decoding_lang/words.txt || \
! cmp $decoding_lang/words.txt $rescoring_lang/words.txt ) && \
( ! cmp $langdir/words.txt $decoding_lang/words.txt ) && \
echo "$0: Warning: vocabularies may be incompatible."

$speed_perturb && suffix=_sp
dir=$exp/chain/tdnn${affix}${suffix}
graph_dir=$dir/${tag}_graph
mfcc_hires=$decode_data_dir/${data_set}_hires


if [ $stage -le 0 ]; then
    # Create MFCCs for the dev/eval sets"
  echo "Creating mfcc's for $data_set"
  
  utils/copy_data_dir.sh $decode_data_dir $mfcc_hires
  
  steps/make_mfcc.sh --cmd "$train_cmd" \
    --nj $n_jobs \
    --mfcc-config conf/mfcc_hires.conf \
    $mfcc_hires \
    $log/mfcc/${data_set}_hires \
    $mfccdir/${data_set}_hires;

  steps/compute_cmvn_stats.sh $mfcc_hires \
    $log/mfcc/${data_set}_hires \
    $mfccdir/${data_set}_hires;

  utils/validate_data_dir.sh $mfcc_hires || utils/fix_data_dir.sh $mfcc_hires 
  echo "Done mfcc's for $data_set"
fi

if [ $stage -le 1 ]; then
  echo "Extracting Ivectors from $data_set"
  steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" \
    --nj $n_jobs \
    $mfcc_hires \
    $ivector_extractor \
    $exp/nnet3/ivectors_${data_set} || exit 1;
fi

if [ $stage -le 2 ]; then
  echo "Making the graph for $dir"
  utils/slurm.pl --mem 50G $log/${tag}_mkgraph.log \
    utils/mkgraph.sh --self-loop-scale \
    1.0 \
    $decoding_lang \
    $dir \
    $graph_dir || exit 1;
    
  echo "Created the graph, log in $graph_dir/mkgraph.log"
fi

if [ $stage -le 3 ]; then
  rm $dir/.error 2>/dev/null || true

  # The wer_output_filter contains a sed command that removes the subword separator 
  # and the command needs to be tailored to the specific boundary marking style.
  echo '#!/bin/sed -f' > local/wer_output_filter
  echo "s/<sil>//g" >> local/wer_output_filter
  echo "s/<UNK>//g" >> local/wer_output_filter
  chmod 777 local/wer_output_filter
  if [[ $boundary_marker == 'wb' ]]; then
    echo "s/ ${sw_separator} //g" >> local/wer_output_filter
  elif [[ $boundary_marker == 'l' ]]; then
    echo "s/ ${sw_separator}//g" >> local/wer_output_filter
  elif [[ $boundary_marker == 'lr' ]]; then
    echo "s/${sw_separator} ${sw_separator}//g" >> local/wer_output_filter
  else
    echo "s/${sw_separator} //g" >> local/wer_output_filter
  fi

    echo "Decoding $data_set"
    (
    steps/nnet3/decode.sh --acwt 1.0 \
      --post-decode-acwt 10.0 \
      --nj $n_jobs \
      --cmd "$decode_cmd --time 0-06" \
      --skip_diagnostics true \
      --stage 0 \
      --online-ivector-dir $exp/nnet3/ivectors_${data_set} \
      $graph_dir \
      $decode_data_dir/${data_set}_hires \
      $dir/${tag}_decode_${data_set} || exit 1;
    
    steps/lmrescore_const_arpa.sh --cmd "$decode_cmd" \
      --stage 0 \
      $decoding_lang \
      $rescoring_lang \
      $decode_data_dir/${data_set}_hires \
      $dir/${tag}_decode_${data_set} \
      $dir/${tag}_decode_${data_set}_rescored || exit 1;
    ) || touch $dir/.error 

    if [ -f $dir/.error ]; then
      echo "$0: something went wrong in decoding"
      exit 1
    fi
fi
echo "Done!"
exit 0;