#!/usr/bin/env bash

# Copyright 2014 QCRI (author: Ahmed Ali)
#           2019 Dongji Gao
# Apache 2.0

# This is an example script for subword implementation
# Modified in 2020 for Icelandic by Svanhvít Lilja Ingólfsdóttir
#                                   David Erik Mollberg

#SBATCH --mem=12G
#SBATCH --output=output.

# set -e - Stop the script if any component returns non-zero
# set -u - Stop the script if any variables are unbound
# set -x - Extreme debug mode
# set -o pipefail - Stop the script if something in a pipeline fail
set -eo pipefail


num_jobs=20
num_decode_jobs=20
decode_gmm=true
stage=0
create_mfcc=true
train_mono=true

lang="test_bpe"
method='bpe'

. utils/parse_options.sh || exit 1;
. path.sh
. cmd.sh


#0_sb_mal_bpe_just_transcripts: subword, malrómur, Byte pair encoding, just transcripts
#1_sb_mal_bpe_althingi: subword, malrómur, byte pair encoding,  LMtext.althingi.txt
#2_sb_mal_bpe_althingi: subword, malrómur, byte pair encoding,  LMtext.althingi.txt  Had some bugs in
#the first run. Mostlikely beacouse I was cleaning up he run script while it was running
#3_sb_mal_bpe_rmh: subword, málrómur, bpe, rmh text
#3_sb_mal_bpe_rmh_V2: subword, málrómur, bpe, rmh text  - Second try as the first run might have had a bug in th LM step


# Audio data paths
AUDIO=/data/asr/malromur/malromur2017/correct

#samromur_root=/data/asr/samromur/samromur_ldc
METADATA=/data/asr/malromur/malromur2017/malromur_metadata.tsv

# Text corpus for the LM
text_corpus=/data/asr/malromur/malromur2017/malromur_corpus.txt


# Todo add dependency check
# E.g. check whether srilm is installed and the directory and two
# files are ok. But not necessary since instructions in readme tell the user to install it.


if [ $stage -le 0 ]; then
  echo ============================================================================
  echo "                		Data Prep			                "
  echo ============================================================================
  python3 local/prep_metadata.py --audio $AUDIO \
  --metadata $METADATA \
  --lang $lang
fi



if [ $stage -le 1 ]; then
  echo ============================================================================
  echo "                		Using $method          "
  echo ============================================================================
  #change this to use another corpus when creating subwords
  #path to corpus used for traning LM.
  num_merges=1000
  #sed "s/[^ ]* //" data/$lang/all/text > data/$lang/all/corpus
  #text_corpus=data/$lang/all/corpus
  
  if [[ $method == 'bpe' ]]; then
    local/subword_methods/bpe.sh $lang \
    $text_corpus \
    $num_merges
  fi
fi

if [ $stage -le 2 ]; then
  echo ============================================================================
  echo "                		Prepare subword text files with $method          "
  echo ============================================================================
  # This is a hack that will be replaced in future commits
  cut -d" " -f2- data/$lang/training/text > data/$lang/training/corpus
  text_corpus=data/$lang/training/corpus
  
  #local/language_modeling/prepare_lm_subword.sh data/$lang/training/text \
  
  
  local/language_modeling/prepare_lm_subword.sh $text_corpus \
  data/$lang/test/text \
  data/$lang/local/dict/lexicon.txt \
  data/$lang/local/lm \
  6
  
  utils/format_lm.sh  data/$lang/lang \
  data/$lang/local/lm/lm.gz \
  data/$lang/local/dict/lexicon.txt \
  data/$lang/lang_test
fi

if [ $stage -le 3 ] && $create_mfcc; then
  echo ===========================================================================
  echo "                		Creating MFCC			                "
  echo ============================================================================
  for i in training test; do
    steps/make_mfcc.sh --cmd "$train_cmd" \
    --nj $num_jobs \
    data/$lang/$i \
    exp/$lang/mfcc/log/make_mfcc \
    exp/$lang/mfcc/$i || error 1 "Failed creating MFCC features";
    
    steps/compute_cmvn_stats.sh data/$lang/$i \
    exp/$lang/mfcc/log/cmvn_stats \
    exp/$lang/mfcc/$i || exit 1;
    
    utils/validate_data_dir.sh data/$lang/$i || utils/fix_data_dir.sh data/$lang/$i || exit 1;
  done
fi

if [ $stage -le 4 ] && $train_mono; then
  echo ============================================================================
  echo "          Train mono system                                               "
  echo ============================================================================
  utils/subset_data_dir.sh data/$lang/training \
  10000 \
  data/$lang/train.10K || exit 1;
  
  steps/train_mono.sh --nj $num_jobs \
  --cmd "$train_cmd" \
  data/$lang/train.10K \
  data/$lang/lang \
  exp/$lang/mono || exit 1;
fi

if [ $stage -le 5 ]; then
  echo ============================================================================
  echo "          Train tri1 delta+deltadelta system                               "
  echo ============================================================================
  echo "$0: Aligning data using monophone system"
  steps/align_si.sh --nj $num_jobs \
  --cmd "$train_cmd" \
  data/$lang/training \
  data/$lang/lang \
  exp/$lang/mono \
  exp/$lang/mono_ali || exit 1;
  
  echo "$0: training triphone system with delta features"
  steps/train_deltas.sh --cmd "$train_cmd" \
  2500 30000 \
  data/$lang/training \
  data/$lang/lang \
  exp/$lang/mono_ali \
  exp/$lang/tri1 || exit 1;
fi

if [ $stage -le 6 ]; then
  echo ============================================================================
  echo "     Train tri2 aligning data and retraining and realigning with lda_mllt   "
  echo ============================================================================
  steps/align_si.sh --nj $num_jobs \
  --cmd "$train_cmd" \
  data/$lang/training \
  data/$lang/lang \
  exp/$lang/tri1 \
  exp/$lang/tri1_ali || exit 1;
  
  steps/train_lda_mllt.sh --cmd "$train_cmd" \
  4000 50000 \
  data/$lang/training \
  data/$lang/lang \
  exp/$lang/tri1_ali \
  exp/$lang/tri2b || exit 1;
fi

if [ $stage -le 7 ]; then
  echo ============================================================================
  echo "          Train tri3 LDA+MLLT+SAT system                                  "
  echo ============================================================================
  echo "$0: Aligning data and retraining and realigning with sat_basis"
  steps/align_si.sh --nj $num_jobs \
  --cmd "$train_cmd" \
  data/$lang/training \
  data/$lang/lang \
  exp/$lang/tri2b \
  exp/$lang/tri2b_ali || exit 1;
  
  steps/train_sat_basis.sh --cmd "$train_cmd" \
  5000 100000 \
  data/$lang/training \
  data/$lang/lang \
  exp/$lang/tri2b_ali \
  exp/$lang/tri3b || exit 1;
  
  steps/align_fmllr.sh --nj $num_jobs \
  --cmd "$train_cmd" \
  data/$lang/training \
  data/$lang/lang \
  exp/$lang/tri3b \
  exp/$lang/tri3b_ali || exit 1;
fi

if [ $stage -le 8 ] && $decode_gmm; then
  echo ============================================================================
  echo "          Decoding tri3                          "
  echo ============================================================================
  tri=tri3b
  utils/mkgraph.sh data/$lang/lang_test \
  exp/$lang/$tri \
  exp/$lang/$tri/graph || exit 1;
  
  steps/decode_fmllr.sh --nj $num_decode_jobs \
  --cmd "$decode_cmd" \
  exp/$lang/$tri/graph \
  data/$lang/test \
  exp/$lang/$tri/decode || exit 1;
fi

echo "$0: training succeed"
exit 0