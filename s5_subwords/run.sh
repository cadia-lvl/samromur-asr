#!/usr/bin/env bash

# Copyright 2014 QCRI (author: Ahmed Ali)
#           2019 Dongji Gao
# Apache 2.0

# This is an example script for subword implementation
# Modified in 2020 for Icelandic by Svanhvít Lilja Ingólfsdóttir 
#                                   David Erik Mollberg

# set -e - Stop the script if any component returns non-zero
# set -u - Stop the script if any variables are unbound
# set -x - Extreme debug mode
# set -o pipefail - Stop the script if something in a pipeline fail
# set -eo pipefail

# standardizes all the sort algorithms 
export LC_ALL=C

num_jobs=50
num_decode_jobs=30
stage=0
lm_order=6
lm_tool='kenlm'
code="sm"
method='bpe'
sw_count=3000
corpora="sm"
tdnn=true

create_mfcc=true
mfcc_dir=exp/$code/mfcc


. utils/parse_options.sh || exit 1;
. path.sh
. cmd.sh 

# Audio data paths 
MALROMUR_AUDIO=/data/asr/malromur/malromur2017/correct

#samromur_root=/data/asr/samromur/samromur_ldc
METADATA=/data/asr/malromur/malromur2017/malromur_metadata.tsv
#METADATA=/home/derik/work/tools/normalize/malromur/normalized_files/malromur_metadata_subset.tsv # A small subest of the corpus, used for fast testing.

# Text corpus for the LM
# text_corpus=/data/asr/malromur/malromur2017/malromur_corpus.txt
text_corpus=/work/derik/language_models/LM_corpus/rmh_test
#text_corpus=/work/derik/language_models/LM_corpus/rmh_2020-11-23_shuffle+malromur

samromur_root=/data/asr/samromur/samromur_ldc

# Todo: Sanity check

decode_lm=/work/derik/samromur-asr/s5_subwords/data/lm_ice/lang_6g_rmh_test
rescore_lm=/work/derik/samromur-asr/s5_subwords/data/lm_ice/lang_10g

if [ $stage -le 0 ]; then
echo ============================================================================
echo "                		Data Prep			                "
echo ============================================================================
  if [ $corpora == 'malromur' ]; then
    local/malromur_prep_data.py -a $MALROMUR_AUDIO \
                                -m $METADATA \
                                -o data/$code 
  
  elif [ $corpora == 'samromur' ]; then
    local/samromur_prep_data.py -a $samromur_root/audio \
                                -m $samromur_root/metadata.tsv \
                                -o data/$code
  elif [ $corpora == 'sm' ]; then
      local/malromur_prep_data.py -a $MALROMUR_AUDIO \
                                  -m $METADATA \
                                  -o data/tmp_malromur 

      local/samromur_prep_data.py -a $samromur_root/audio \
                                  -m $samromur_root/metadata.tsv \
                                  -o data/tmp_samromur

      # Here we add all the malromur data as training data but keep the defined dev and test from samrómur
      utils/combine_data.sh data/$code/train data/tmp_malromur/train data/tmp_samromur/train data/tmp_malromur/test data/tmp_malromur/dev
      utils/combine_data.sh data/$code/test data/tmp_samromur/test
      utils/combine_data.sh data/$code/dev data/tmp_samromur/dev
      rm -r data/tmp_malromur data/tmp_samromur
  fi
fi


if [ $stage -le 1 ]; then
echo ============================================================================
echo "               Create $method model and preparing text files         "
echo ============================================================================
  # The steps in the is section are the same for all three methods. First we learm to create subwords from 
  # a given text corpus then we apply that model to text files in data/$code/[train|test|eval].
  # We store the models/segmentation pair codes for the different subwords methods 
  # in data/$code/sw. Where sw stands for subwords. Next we create the lexicon by finding
  # all the diffrent subwords create when we tokenize the train/text file. These step have 
  # their own script depending on method choosen. Next we prepare the lexicon and the rest of
  # contentes in the dict and lang folders. 

  subword_dir=data/$code/sw
  mkdir -p $subword_dir

  if [[ $method == 'bpe' ]]; then
    # Form a given text corpus we learn to create subwords we store the "model" as pair_codes
    # Note: Maybe we should be using the transcripts to learn the pair codes because that will
    # make up the words that we try to model.
    #transcripts=/data/asr/malromur/malromur2017/malromur_corpus.txt

    python3 local/sw_methods/bpe/learn_bpe.py -i $text_corpus \
                                              -s $sw_count > $subword_dir/pair_codes
    
    # Using the pair_codes we subword tokenize the kaldi format text files
    for x in train dev test; do
      #echo "$0: Applying BPE to $x"
      ./local/sw_methods/bpe/prepare_subword_text.sh data/$code/${x}/text \
                                                     $subword_dir/pair_codes \
                                                     data/$code/${x}/text \
                                                     || error "Failed applying BPE"                                                     
    done
    
    # Tokenize the text corpus that will be used for language model training
    python3 local/sw_methods/bpe/apply_bpe.py -i $text_corpus \
                                              --codes $subword_dir/pair_codes \
                                              | sort -u > $subword_dir/text_corpus

  
  elif [[ $method == 'unigram' || $method == 'sp_bpe' ]]; then

    model=$subword_dir/unigram_${sw_count}

    # Using the text corpus create the subword "model" and store it as $model
    python3 local/sw_methods/sp/train_sp.py -i $text_corpus \
                                            -o $model \
                                            -v $sw_count \
                                            -t $method \
                                            -l "True" \
                                            || error "Failed training a ${method} model"

    # Using the model we subword tokenize the kaldi format text files
    for x in train dev test ; do
      cp data/$code/$x/text data/$code/$x/text.old
      python3 local/sw_methods/sp/apply_sp.py -m $model \
                                              -t $method \
                                              --kaldi_text "True" \
                                              -i data/$code/$x/text.old > data/$code/$x/text \
                                              || error "Failed applying the ${method} model"
    done 
    python3 local/sw_methods/sp/apply_sp.py -m $model \
                                            -t $method \
                                            -i $text_corpus \
                                             > $subword_dir/text_corpus


  elif [[ $method == 'morfessor' ]]; then
    # This step is not fully complete, I had to setup morfessor in 
    # Had to use conda env to install package. 
    # Is avalible here https://github.com/Waino/morfessor-emprune
  
    ./local/sw_methods/morfessor/train_morfessor.sh $text_corpus \
                                                    $sw_count \
                                                    $subword_dir

    for x in train dev test; do
      #echo "$0: Applying BPE to $x"  
      ./local/sw_methods/morfessor/apply_morfessor.sh data/$code/${x}/text \
                                                      $subword_dir \
                                                      data/$code/${x}/text \
                                                      'true' \
                                                      || error "Failed applying BPE"                                                     
    done

    ./local/sw_methods/morfessor/apply_morfessor.sh $text_corpus \
                                                    $subword_dir \
                                                    $subword_dir/text_corpus 
  fi 
  
  echo "$0: Preparing lexicon, dict folder and lang folder" 
  cut -d" " -f2- data/$code/train/text >> $subword_dir/text_corpus
  local/prepare_dict_subword.sh $subword_dir/text_corpus \
                                $subword_dir \
                                data/$code/local/dict \
                                || error "Failed preparing lang"

  utils/subword/prepare_lang_subword.sh data/$code/local/dict \
                                        "<UNK>" \
                                        data/$code/local/lang \
                                        data/$code/lang \
                                        || error "Failed preparing lang"
fi

if [ $stage -le 2 ]; then
echo ============================================================================
echo "                		Prepare LM with subword text files with $method          "
echo ============================================================================

  if [ $lm_tool == 'srilm' ]; then
    local/lm/prepare_lm_subword.sh $subword_dir/text_corpus \
                                data/$code/dev/text \
                                data/$code/local/dict/lexicon.txt \
                                data/$code/local/lm \
                                6               

    utils/format_lm.sh  data/$code/lang \
                        data/$code/local/lm/lm.gz \
                        data/$code/local/dict/lexicon.txt \
                        data/$code/lang_${lm_order}g
    
  elif [ $lm_tool == 'kenlm' ]; then
    lm_order=6
    echo "Preparing an ${lm_order}g LM"
    $train_cmd --mem 80G "logs/make_LM_${lm_order}g_pruned.log" \
               local/lm/make_LM.sh \
               --order $lm_order \
               --pruning "0 2 5 10" \
               --carpa false \
               $subword_dir/text_corpus_full_uniq \
               data/$code/lang \
               data/$code/local/dict/lexicon.txt \
               data/lm_ice \
               "${method}${sw_count}_pruned" \
               || error 1 "Failed creating an pruned ${lm_order}g LM";

    echo "Done creating an ${lm_order}g. The log is available logs/make_LM_${lm_order}g.log"
  fi
fi        


if [ $stage -le 3 ] && $create_mfcc; then
echo ===========================================================================
echo "                		Creating MFCC			                "
echo ============================================================================
  for x in train dev test; do
    steps/make_mfcc.sh --cmd "$train_cmd" \
                       --nj $num_jobs \
                       data/$code/$x \
                       $mfcc_dir/log/make_mfcc \
                       $mfcc_dir/$x || error "Failed creating MFCC features"

    steps/compute_cmvn_stats.sh data/$code/$x \
                                exp/$code/mfcc/log/cmvn_stats \
                                $mfcc_dir/$x || exit 1;
    
    utils/validate_data_dir.sh data/$code/$x || utils/fix_data_dir.sh data/$code/$x || error "Failed"
  done
fi

if [ $stage -le 4 ]; then
echo ============================================================================
echo "          Train mono system                                               "
echo ============================================================================
  utils/subset_data_dir.sh data/$code/train \
                           10000 \
                           data/$code/train.10K || error "Failed"

  steps/train_mono.sh --nj $num_jobs \
                      --cmd "$train_cmd" \
                      data/samromur/train.10K \
                      data/$code/lang \
                      exp/$code/mono || error "Failed"
fi

if [ $stage -le 5 ]; then
  echo ============================================================================
  echo "          Train tri1 delta+deltadelta system                               "
  echo ============================================================================
  echo "$0: Aligning data using monophone system"
  steps/align_si.sh --nj $num_jobs \
                    --cmd "$train_cmd" \
                    data/$code/train \
                    data/$code/lang \
                    exp/$code/mono \
                    exp/$code/mono_ali || exit 1;

  echo "$0: training triphone system with delta features"
  steps/train_deltas.sh --cmd "$train_cmd" \
                        2500 30000 \
                        data/$code/train \
                        data/$code/lang \
                        exp/$code/mono_ali \
                        exp/$code/tri1 || exit 1;
fi

if [ $stage -le 6 ]; then
  echo ============================================================================
  echo "     Train tri2 aligning data and retraining and realigning with lda_mllt   "
  echo ============================================================================
  steps/align_si.sh --nj $num_jobs \
                    --cmd "$train_cmd" \
                    data/$code/train \
                    data/$code/lang \
                    exp/$code/tri1 \
                    exp/$code/tri1_ali || exit 1;

  steps/train_lda_mllt.sh --cmd "$train_cmd" \
                          4000 50000 \
                          data/$code/train \
                          data/$code/lang \
                          exp/$code/tri1_ali \
                          exp/$code/tri2b || exit 1;
fi

if [ $stage -le 7 ]; then
  echo ============================================================================
  echo "          Train tri3 LDA+MLLT+SAT system                                  "
  echo ============================================================================
  echo "$0: Aligning data and retraining and realigning with sat_basis"
  steps/align_si.sh --nj $num_jobs \
                    --cmd "$train_cmd" \
                    data/$code/train \
                    data/$code/lang \
                    exp/$code/tri2b \
                    exp/$code/tri2b_ali || exit 1;

  steps/train_sat_basis.sh --cmd "$train_cmd" \
                           5000 100000 \
                           data/$code/train \
                           data/$code/lang \
                           exp/$code/tri2b_ali \
                           exp/$code/tri3b || exit 1;

  steps/align_fmllr.sh --nj $num_jobs \
                        --cmd "$train_cmd" \
                        data/$code/train \
                        data/$code/lang \
                        exp/$code/tri3b \
                        exp/$code/tri3b_ali || exit 1;
fi

if [ $stage -le 8 ]; then
  echo ============================================================================
  echo "          Decoding tri3                          "
  echo ============================================================================
  tri=tri3b
  utils/mkgraph.sh $decode_lm \
                   exp/$code/$tri \
                   exp/$code/$tri/graph || exit 1;

  for dir in dev test; do
    (
    #steps/decode_fmllr.sh --nj $num_decode_jobs \
    #                      --cmd "$decode_cmd" \
    #                      exp/$code/$tri/graph \
    #                      data/$code/$dir \
    #                      exp/$code/$tri/decode_${dir};

    steps/lmrescore_const_arpa.sh --cmd "$decode_cmd" \
                                  $decode_lm \
                                  $rescore_lm \
                                  data/$code/$dir \
                                  exp/$code/$tri/decode_$dir \
                                  exp/$code/$tri/decode_${dir}_rescored
    ) &
  done
  wait
  
  # WER info:
  for x in exp/$code/*/decode_{test,dev}_rescored; do
    [ -d "$x" ] && grep WER "$x"/wer_* | utils/best_wer.sh;
  done > RESULTS
fi


if [ $stage -le 9 ] && $tdnn; then
    affix="_${code}"

    echo data/$code/train data/$code $code
    nohup local/chain/run_tdnn.sh --stage 0 \
                            --affix $affix \
                            --decoding-lang $decode_lm \
                            --rescoring-lang $rescore_lm \
                            --langdir data/$code/lang \
                            --gmm $code/tri3b \
                            data/$code/train \
                            data/$code/ \
                            $code \
                            >> logs/$code/tdnn$affix.log 2>&1 &
    
    
    for x in exp/chain/tdnn${affix}_sp/decode*; do 
    
      [ -d $x ] && grep WER $x/wer_* | utils/best_wer.sh; 
    
    done >> RESULTS
    
fi


echo "$0: training succeeded"
exit 0