#!/usr/bin/env bash

# Copyright 2014 QCRI (author: Ahmed Ali)
#           2019 Dongji Gao
# Apache 2.0

# This is an example script for subword implementation
# Modified in 2020 for Icelandic by Svanhvít Lilja Ingólfsdóttir 
#                                   David Erik Mollberg

#SBATCH --mem=12G
#SBATCH --output=logs/subest_baseline_unigram.log

# set -e - Stop the script if any component returns non-zero
# set -u - Stop the script if any variables are unbound
# set -x - Extreme debug mode
# set -o pipefail - Stop the script if something in a pipeline fail
set -exo pipefail

# standardizes all the sort algorithms 
export LC_ALL=C


num_jobs=20
num_decode_jobs=20
decode_gmm=true
stage=0
create_mfcc=true
train_mono=true

lang="subest_baseline_unigram"
method='unigram'
sw_count=1000


. utils/parse_options.sh || exit 1;
. path.sh
. cmd.sh 

# Audio data paths 
AUDIO=/data/asr/malromur/malromur2017/correct

#samromur_root=/data/asr/samromur/samromur_ldc
#METADATA=/data/asr/malromur/malromur2017/malromur_metadata.tsv
METADATA=/home/derik/work/tools/normalize/malromur/normalized_files/malromur_metadata_subset.tsv # A small subest of the corpus, used for fast testing.

# Text corpus for the LM
text_corpus=/data/asr/malromur/malromur2017/malromur_corpus.txt


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
  # The steps in the is section are the same for all three methods. First we learm to create subwords from 
  # a given text corpus then we apply that model to text files in data/$lang/[train|test|eval].
  # We store the models/segmentation pair codes for the different subwords methods 
  # in data/$lang/sw. Where sw stands for subwords. Next we create the lexicon by finding
  # all the diffrent subwords create when we tokenize the train/text file. These step have 
  # their own script depending on method choosen. Next we prepare the lexicon and the rest of
  # contentes in the dict and lang folders. 

  subword_dir=data/$lang/sw
  mkdir -p $subword_dir

  if [[ $method == 'bpe' ]]; then
    # Form a given text corpus we learn to create subwords we store the "model" as pair_codes
    python3 local/sw_methods/bpe/learn_bpe.py -i $text_corpus \
                                              -s $sw_count > $subword_dir/pair_codes
    
    # Using the pair_codes we subword tokenize the kaldi format text files
    for x in train test eval; do
      #echo "$0: Applying BPE to $x"
      ./local/sw_methods/bpe/prepare_subword_text.sh data/$lang/${x}/text \
                                                     $subword_dir/pair_codes \
                                                     data/$lang/${x}/text \
                                                     || error "Failed applying BPE"                                                     
    done
    
    # Tokenize the text corpus that will be used for language model training
    python3 local/sw_methods/bpe/apply_bpe.py -i $text_corpus \
                                              --codes $subword_dir/pair_codes \
                                              > $subword_dir/text_corpus

    # We again subword tokenize to create a subword lexicon
    #python3 local/sw_methods/bpe/apply_bpe.py -i data/$lang/train/tokens \
    #                                          --codes $subword_dir/pair_codes \
    #                                          | sed 's/ /\n/g' | sort -u > $subword_dir/subwords
  
    elif [[ $method == 'unigram' || $method == 'sp_bpe' ]]; then
    
    model=$subword_dir/unigram_${sw_count}

    # Form a given text corpus we learn to create subwords we store the "model" as in $model
    python3 local/sw_methods/sp/train_sp.py -i $text_corpus \
                                            -o $model \
                                            -v $sw_count \
                                            -t $method \
                                            || error "Failed training a ${method} model"

    # Using the model we subword tokenize the kaldi format text files
    for x in train test ; do
      cp data/$lang/$x/text data/$lang/$x/text.old
      python3 local/sw_methods/sp/apply_sp.py -m $model \
                                              -t $method \
                                              --kaldi_text "True" \
                                              -i data/$lang/$x/text.old > data/$lang/$x/text \
                                              || error "Failed applying the ${method} model"
    done 
    python3 local/sw_methods/sp/apply_sp.py -m $model \
                                            -t $method \
                                            -i $text_corpus \
                                             > $subword_dir/text_corpus

    # Note: What text file should we use here, if we use the text_corpus the subword lexicon 
    # might increase.  
    #cp $subword_dir/text_corpus $subword_dir/text_corpus_plus_text
    #cut -d" " -f2- data/$lang/train/text >> $subword_dir/text_corpus_plus_text
    #cut -d" " -f2- data/$lang/train/text | sed 's/ /\n/g' | LC_ALL=C sort -u | grep -v '^[[:space:]]*$' > $subword_dir/subwords 
    #cut -d" " -f2- $subword_dir/text_corpus | sed 's/ /\n/g' | sort -u | grep -v '^[[:space:]]*$' > $subword_dir/subwords 

  elif [[ $method == 'morfessor' ]]; then
    echo "To be done"
  fi 
  
  #cut -d" " -f2- data/$lang/train/text | sed 's/ /\n/g' | grep -v '^[[:space:]]*$' | sort -u > $subword_dir/subwords 

  # The following scripts should be run independant of which subword method is choosen
  #echo "$0: Preparing lexicon"
  #python3 local/prepare_lexicon.py --i $subword_dir/subwords \
  #                                 --o $subword_dir/subword_lexicon \
  #                                 --is_subword True

  echo "$0: Preparing lexicon, dict folder and lang folder" 

  cut -d" " -f2- data/$lang/train/text >> $subword_dir/text_corpus
  local/prepare_dict_subwordV2.sh $subword_dir/text_corpus \
                                  $subword_dir \
                                  data/$lang/local/dict \
                                  || error "Failed preparing lang"

  utils/subword/prepare_lang_subword.sh data/$lang/local/dict \
                                        "<UNK>" \
                                        data/$lang/local/lang \
                                        data/$lang/lang \
                                        || error "Failed preparing lang"
fi

if [ $stage -le 2 ]; then
echo ============================================================================
echo "                		Prepare LM with subword text files with $method          "
echo ============================================================================

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
  for x in train test; do
    steps/make_mfcc.sh --cmd "$train_cmd" \
                       --nj $num_jobs \
                       data/$lang/$x \
                       exp/$lang/mfcc/log/make_mfcc \
                       exp/$lang/mfcc/$x || error "Failed creating MFCC features"

    steps/compute_cmvn_stats.sh data/$lang/$x \
                                exp/$lang/mfcc/log/cmvn_stats \
                                exp/$lang/mfcc/$x || exit 1;
    
    utils/validate_data_dir.sh data/$lang/$x || utils/fix_data_dir.sh data/$lang/$x || error "Failed"
  done
fi

if [ $stage -le 4 ] && $train_mono; then
echo ============================================================================
echo "          Train mono system                                               "
echo ============================================================================
  utils/subset_data_dir.sh data/$lang/train \
                           10000 \
                           data/$lang/train.10K || error "Failed"

  steps/train_mono.sh --nj $num_jobs \
                      --cmd "$train_cmd" \
                      data/$lang/train.10K \
                      data/$lang/lang \
                      exp/$lang/mono || error "Failed"
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