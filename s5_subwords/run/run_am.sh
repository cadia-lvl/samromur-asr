#!/usr/bin/env bash

export LC_ALL=C

num_jobs=20
stage=0

. ./cmd.sh
. ./path.sh
./setup.sh
. utils/parse_options.sh

METADATA=../demo_data/metadata.tsv
AUDIO=../demo_data/audio
TEXT_CORPUS=../demo_data/text_corpus

data=data
exp=exp
log=logs

mkdir -p $data $exp $log

if [ $stage -le 0 ]; then
  echo ============================================================================
  echo "                		Data prep			                              "
  echo ============================================================================
    ./local/samromur_prep_data.py --a $AUDIO \
      --m $METADATA \
      --o $data 
fi

if [ $stage -le 1 ]; then
  echo ============================================================================
  echo "       		Creating MFCC and computing cmvn stats                        "
  echo ============================================================================
    for x in train dev test; do
      steps/make_mfcc.sh --cmd "$train_cmd" \
        --nj $num_jobs \
        $data/$x \
        $log/mfcc/log_${x} \
        $exp/mfcc/$x 

      steps/compute_cmvn_stats.sh $data/$x \
        $log/mfcc/log_${x}  \
        $exp/mfcc/$x 
      
      utils/validate_data_dir.sh $data/$x || utils/fix_data_dir.sh $data/$x 
    done
fi

if [ $stage -le 2 ]; then
  echo ============================================================================
  echo "           	Preparing lexicon, dict folder and lang folder             "
  echo ============================================================================
  local/prepare_dict.sh $TEXT_CORPUS \
    $data/local/tmp/base \
    $data/dict/base 
  
  utils/prepare_lang.sh $data/dict/base  \
    "<UNK>" \
    $data/local/tmp/base \
    $data/lang/base 
fi

if [ $stage -le 3 ]; then
  echo ============================================================================
  echo "           	Aligning data and training the acoustic model                 "
  echo ============================================================================
  subset_size=10000
  # DemoData: To run this script with the demo data we need to change the subset size
  train_size=$(wc -l $data/train/text | cut -d" " -f1)
  if [ $train_size -le $subset_size ]; then
    subset_size=$train_size
  fi

  echo "$0: Creating subset for monophone training"
  utils/subset_data_dir.sh $data/train \
    $subset_size \
    $data/train/train.${subset_size}K 

  echo "$0: Training mono system"
  steps/train_mono.sh --nj $num_jobs --cmd "$train_cmd" \
    $data/train/train.${subset_size}K \
    $data/lang/base \
    $exp/mono 
  
  echo "$0: Aligning data using monophone system" 
  steps/align_si.sh --nj $num_jobs \
    --cmd "$train_cmd" \
    $data/train \
    $data/lang/base \
    $exp/mono \
    $exp/mono_ali 
    
  echo "$0: Training triphone system with delta features"
  steps/train_deltas.sh --cmd "$train_cmd" \
    2500 30000 \
    $data/train \
    $data/lang/base \
    $exp/mono_ali \
    $exp/tri1 

  echo "$0: Aligning with tri1 model"
  steps/align_si.sh --nj $num_jobs \
    --cmd "$train_cmd" \
    $data/train \
    $data/lang/base \
    $exp/tri1 \
    $exp/tri1_ali
  
  echo "$0: Training with lda_mllt "
  steps/train_lda_mllt.sh --cmd "$train_cmd" \
    4000 50000 \
    $data/train \
    $data/lang/base \
    $exp/tri1_ali \
    $exp/tri2b 

  echo "$0: Aligning with lda_mllt model"
  steps/align_si.sh --nj $num_jobs \
    --cmd "$train_cmd" \
    $data/train \
    $data/lang/base \
    $exp/tri2b \
    $exp/tri2b_ali 

  echo "$0: Training tri3b LDA+MLLT+SAT system"
  steps/train_sat_basis.sh --cmd "$train_cmd" \
    5000 100000 \
    $data/train \
    $data/lang/base \
    $exp/tri2b_ali \
    $exp/tri3b 
fi

if [ $stage -le 4 ]; then
  echo ============================================================================
  echo "          TDNN training                                       "
  echo ============================================================================
  ./run/run_tdnn.sh --stage 0 \
    --langdir $data/lang/base \
    --data $data/train --exp $exp \
    $data/train \
    $data \
    >> $log/am_tdnn.log 2>&1
fi