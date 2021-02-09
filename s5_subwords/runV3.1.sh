#!/usr/bin/env bash

# Copyright 2014 QCRI (author: Ahmed Ali)
#           2019 Dongji Gao
# Apache 2.0

# This is an example script for subword implementation
# Modified in 2020 for Icelandic by Svanhvít Lilja Ingólfsdóttir 
#                                   David Erik Mollberg

#SBATCH --mem=12G
#SBATCH --output=subset_bpe_improvement.log

# set -e - Stop the script if any component returns non-zero
# set -u - Stop the script if any variables are unbound
# set -x - Extreme debug mode
# set -o pipefail - Stop the script if something in a pipeline fail
set -exo pipefail


num_jobs=20
num_decode_jobs=20
decode_gmm=true
stage=0
create_mfcc=true
train_mono=true

lang="test_bpe"
method='bpe'
sw_count=1000

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
#METADATA=/data/asr/malromur/malromur2017/malromur_metadata.tsv
METADATA=/home/derik/work/tools/normalize/malromur/normalized_files/malromur_metadata_subset.tsv

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
echo "               Create $method model and preparing text files         "
echo ============================================================================
  # We store the models/segmentation pair codes for the different subwords methods 
  # in data/$lang/sw. Where sw stands for subwords.
  subword_dir=data/$lang/sw
  mkdir -p $subword_dir

  if [[ $method == 'bpe' ]]; then
    # Form a given text corpus we learn to create subwords we store the "model" as pair_codes
    python3 local/sw_methods/bpe/learn_bpe.py -i $text_corpus \
                                              -s $sw_count > $subword_dir/pair_codes
    
    # Using the pair_codes we subword tokenize the kaldi format text files
    for x in train test eval; do
      ./local/sw_methods/bpe/prepare_subword_text.sh data/$lang/${x}/text \
                                                     $subword_dir/pair_codes \
                                                     data/$lang/${x}/text 
    
    # We again subword tokenize to create a subword lexicon
    python3 local/sw_methods/bpe/apply_bpe.py -i data/$lang/train/tokens \
                                              --codes $subword_dir/pair_codes \
                                              | sed 's/ /\n/g' | sort -u > $subword_dir/subwords
    done

  elif [[ $method == 'unigram' || $method == 'sp_bpe' ]]; then
    echo "To be done"
  elif [[ $method == 'morfessor' ]]; then
    echo "To be done"
  fi 
  # The following scripts should be run independant of which subword method is chosen

  echo "$0: Preparing lexicon"
  python3 local/prepare_lexicon.py --i $subword_dir/subwords \
                                   --o $subword_dir/subword_lexicon \
                                   --is_subword True

  echo "$0: Preparing lexicon, dict folder and lang folder" 
  local/prepare_dict_subword.sh $subword_dir/subword_lexicon \
                                data/$lang/train \
                                data/$lang/local/dict

  utils/subword/prepare_lang_subword.sh data/$lang/local/dict \
                                        "<UNK>"\
                                        data/$lang/local/lang \
                                        data/$lang/lang
fi

if [ $stage -le 2 ]; then
echo ============================================================================
echo "                		Prepare LM with subword text files with $method          "
echo ============================================================================

  echo "Applying $method to $text_corpus"
  if [[ $method == 'bpe' ]]; then
    python3 local/sw_methods/bpe/apply_bpe.py -i $text_corpus \
                                                   --codes $subword_dir/pair_codes \
                                                   > $subword_dir/text_corpus

  elif [[ $method == 'unigram' || $method == 'sp_bpe' ]]; then
    echo "To be done"
  elif [[ $method == 'morfessor' ]]; then
    echo "To be done"
  fi 

  local/lm/prepare_lm_subword.sh $subword_dir/text_corpus \
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
  for i in train test; do
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
  utils/subset_data_dir.sh data/$lang/train \
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
                    data/$lang/train \
                    data/$lang/lang \
                    exp/$lang/mono \
                    exp/$lang/mono_ali || exit 1;

  echo "$0: training triphone system with delta features"
  steps/train_deltas.sh --cmd "$train_cmd" \
                        2500 30000 \
                        data/$lang/train \
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
                    data/$lang/train \
                    data/$lang/lang \
                    exp/$lang/tri1 \
                    exp/$lang/tri1_ali || exit 1;

  steps/train_lda_mllt.sh --cmd "$train_cmd" \
                          4000 50000 \
                          data/$lang/train \
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
                    data/$lang/train \
                    data/$lang/lang \
                    exp/$lang/tri2b \
                    exp/$lang/tri2b_ali || exit 1;

  steps/train_sat_basis.sh --cmd "$train_cmd" \
                           5000 100000 \
                           data/$lang/train \
                           data/$lang/lang \
                           exp/$lang/tri2b_ali \
                           exp/$lang/tri3b || exit 1;

  steps/align_fmllr.sh --nj $num_jobs \
                        --cmd "$train_cmd" \
                        data/$lang/train \
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