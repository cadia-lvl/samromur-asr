#!/usr/bin/env bash
# Copyright   2020 Reykjavik University (Author: Judy Fong - judyfong@ru.is)
# Apache 2.0
#
# See ../README.txt for more info on data required.
#SBATCH --output=logs/samrun%J.out
#SBATCH --nodelist=terra

. ./cmd.sh
. ./path.sh
# setup the steps and utils directories
. ./setup.sh

set -euo pipefail

samromur_root=samromur
stage=0

. utils/parse_options.sh

#TODO: set the samromur data and metadata variables within path.sh
mfccdir=`pwd`/mfccs
num_jobs=10

if [ $stage -le 0 ]; then
  echo "Create training data from samromur training"
  local/samromur_data_prep.sh $samromur_root training data
  local/samromur_data_prep.sh $samromur_root test data
  local/samromur_data_prep.sh $samromur_root eval data

  utils/combine_data.sh data/train data/samromur_training
  utils/combine_data.sh data/dev data/samromur_test
  utils/combine_data.sh data/eval data/samromur_eval
  utils/fix_data_dir.sh data/train
  utils/fix_data_dir.sh data/dev
  utils/fix_data_dir.sh data/eval
fi

# Prepare features
if [ $stage -le 1 ]; then
  echo "Make mfccs"
  # Make MFCCs for each dataset
  for name in train dev eval; do
    steps/make_mfcc.sh --mfcc-config conf/mfcc.conf \
      --nj ${num_jobs} --cmd "$train_cmd --max-jobs-run 99" \
      data/${name} exp/make_mfcc/${name} $mfccdir
    utils/fix_data_dir.sh data/${name}
  done
fi

if [ $stage -le 2 ]; then
  echo "Comute cmvn"
  for name in train dev eval; do
    steps/compute_cmvn_stats.sh data/${name} exp/make_mfcc/${name} $mfccdir
    utils/fix_data_dir.sh data/${name}
    utils/validate_data_dir.sh data/${name}
  done
fi

if [ $stage -le 3 ]; then
  echo "Prepare dict and lang directories"
  local/prep_samromur_lang.sh data/train/text data
fi

if [ $stage -le 4 ]; then
  echo "Create 3gram language model from kenlm"
  cat data/train/text | cut -d' ' -f2- | sed -e \
 's/[,.?!]//g' > data/text_lm_training.txt

  mkdir -p data/lang_3gram

  # language  modeling files are typically in data/lang_Xgram
  $big_memory_cmd logs/make_LM_3gsmall.log local/make_LM.sh --order 3 \
  --small true --carpa false data/text_lm_training.txt data/lang/ \
  data/local/dict/lexicon.txt data/lang_3gram
fi

# train a monophone system
if [ $stage -le 5 ]; then
  utils/subset_data_dir.sh --shortest data/train 500 data/train_500short

  echo "Train monophone model"
  steps/train_mono.sh --boost-silence 1.25 --nj 5 --cmd "$train_cmd" \
    data/train_500short data/lang exp/mono

  # TODO: Understand why we use lang_nosp here...
  echo "Create decoding graph"
  (
    utils/mkgraph.sh data/lang_3gsmall \
      exp/mono exp/mono/graph_3gram
    for test in dev; do
      steps/decode.sh --nj ${num_jobs} --cmd "$decode_cmd" exp/mono/graph_3gram \
        data/$test exp/mono/decode_3gram_$test
    done
  )&

  echo "Create align"
  steps/align_si.sh --boost-silence 1.25 --nj 5 --cmd "$train_cmd" \
    data/train data/lang exp/mono exp/mono_ali_train
fi

# train a first delta + delta-delta triphone(tri1) system on all utterances
if [ $stage -le 6 ]; then
  steps/train_deltas.sh --boost-silence 1.25 --cmd "$train_cmd" \
    2000 10000 data/train data/lang exp/mono_ali_train exp/samromur_tri1
fi

exit 0
# TODO: before decoding create a tgmed or tglarge arpalm
if [ $stage -eq 7 ]; then
  # decode using the tri1 model
  (
    utils/mkgraph.sh data/lang_3gsmall \
      exp/samromur_tri1 exp/samromur_tri1/graph_3gsmall
    for test in dev; do
      steps/decode.sh --nj 5 --cmd "$decode_cmd" exp/samromur_tri1/graph_tgsmall \
      data/$test exp/samromur_tri1/decode_3gsmall_$test
      steps/lmrescore.sh --cmd "$decode_cmd" data/lang_{3gsmall,tgmed} \
        data/$test exp/samromur_tri1/decode_{3gsmall,tgmed}_$test
      steps/lmrescore_const_arpa.sh \
        --cmd "$decode_cmd" data/lang_{3gsmall,tglarge} \
        data/$test exp/samromur_tri1/decode_{3gsmall,tglarge}_$test
    done
  )&

  steps/align_si.sh --nj 5 --cmd "$train_cmd" \
    data/train data/lang exp/samromur_tri1 exp/tri1_ali_train
fi

