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
code="libri"
method='bpe'
sw_count=3000
tdnn=true
create_mfcc=true


libre_data=/work/derik/librispeech/LibriSpeech
text_corpus=/work/derik/librispeech/librispeech-lm-norm.txt

decode_lm=/home/derik/work/samromur-asr/s5_subwords/data_ISP/libri/lm/lang_6g
rescore_lm=/home/derik/work/samromur-asr/s5_subwords/data_ISP/libri/lm/lang_8g

data=data_ISP
exp=exp_ISP

mfcc_dir=$exp/$code/mfcc

. utils/parse_options.sh || exit 1;
. path.sh
. cmd.sh 

subword_dir=$data/$code/sw
mkdir -p $subword_dir


# ln -s ../../kaldi/egs/librispeech/s5


if [ $stage -le 0 ]; then
echo ============================================================================
echo "                		Data Prep			                "
echo ============================================================================
  
  for part in dev-clean test-clean dev-other test-other train-clean-100; do
    local/libri/data_prep.sh $libre_data/$part $data/$code/$(echo $part | sed s/-/_/g)
  done
fi

if [ $stage -le 1 ]; then
echo ============================================================================
echo "               Create $method model and preparing text files         "
echo ============================================================================

  python3 local/sw_methods/bpe/learn_bpe.py -i $text_corpus \
                                            -s $sw_count > $subword_dir/pair_codes

  for x in dev_clean test_clean dev_other test_other train_clean_100; do
    echo "$0: Applying BPE to $x"
    ./local/sw_methods/bpe/prepare_subword_text.sh $data/$code/${x}/text \
                                                    $subword_dir/pair_codes \
                                                    $data/$code/${x}/text \
                                                    || error "Failed applying BPE"                                                     
  done
  
  # Tokenize the text corpus that will be used for language model training
  python3 local/sw_methods/bpe/apply_bpe.py -i $text_corpus \
                                            --codes $subword_dir/pair_codes \
                                            | sort -u > $subword_dir/text_corpus
  
  echo "$0: Preparing lexicon, dict folder and lang folder" 
  cut -d" " -f2- $data/$code/train_clean_100/text >> $subword_dir/text_corpus
  local/prepare_dict_subword.sh $subword_dir/text_corpus \
                                $subword_dir \
                                $data/$code/local/dict \
                                || error "Failed preparing lang"

  utils/subword/prepare_lang_subword.sh $data/$code/local/dict \
                                        "<UNK>" \
                                        $data/$code/local/lang \
                                        $data/$code/lang \
                                        || error "Failed preparing lang"
fi

if [ $stage -le 2 ]; then
echo ============================================================================
echo "                		Prepare LM with subword text files with $method          "
echo ============================================================================
    lm_order=8
    echo "Preparing an ${lm_order}g LM"
    nohup $train_cmd --mem 90G "$code/make_LM_${lm_order}g_pruned.log" \
               local/lm/make_LM.sh \
               --order $lm_order \
               --pruning "0 2 5 10" \
               --carpa false \
               $subword_dir/text_corpus \
               $data/$code/lang \
               $data/$code/local/dict/lexicon.txt \
               data/lm_eng \
               "${method}${sw_count}_pruned" \
               || error 1 "Failed creating an pruned ${lm_order}g LM";

  nohup $train_cmd --mem 90G "logs/$code/make_LM_${lm_order}g_rescoring.log" \
               local/lm/make_LM.sh \
                  --order $lm_order  \
                  --pruning "0 2" \
                  --carpa true \
                  $subword_dir/text_corpus \
                  $data/$code/lang \
                  $data/$code/local/dict/lexicon.txt \
                  $data/lm_eng \
                  "${method}${sw_count}_rescore" \
                  || error 1 "Failed creating an rescore ${lm_order}g LM";

    echo "Done creating an ${lm_order}g. The log is available logs/make_LM_${lm_order}g.log"
fi        


if [ $stage -le 3 ] && $create_mfcc; then
echo ===========================================================================
echo "                		Creating MFCC			                "
echo ============================================================================
  num_jobs=30
  for x in train_clean_100 dev_clean test_clean dev_other test_other ; do

    nohup steps/make_mfcc.sh --cmd "$train_cmd" \
                       --nj $num_jobs \
                       $data/$code/$x \
                       $mfcc_dir/log/make_mfcc \
                       $mfcc_dir/$x \
                       >> logs/$code/mfcc_${x}.log 2>&1 &

    steps/compute_cmvn_stats.sh $data/$code/$x \
                                $exp/$code/mfcc/log/cmvn_stats \
                                $mfcc_dir/$x 
    
    utils/validate_data_dir.sh $data/$code/$x || utils/fix_data_dir.sh $data/$code/$x 
  done
fi


if [ $stage -le 4 ]; then
echo ===========================================================================
echo "                		create subesets			                "
echo ============================================================================

  for x in 2837 5674 11349 22697 45394 90788; do
    code='althingi'
    data=data_ISP
    x=600
    utils/subset_data_dir.sh --speakers $data/$code/train/ 388700 $data/$code/train_${x}h
    cut -d" " -f2 $data/$code/train_${x}h/utt2dur | awk '{s+=$1} END {print s/3600}' 

    cut -d" " -f2 $data/$code/train_${x}h/utt2dur | awk '{s+=$1} END {print s}'  
  done

  utils/combine_data.sh 

  cut -d" " -f2 $data/libri/train_subset/utt2dur | awk '{s+=$1} END {print s}' | 

fi



if [ $stage -le 4 ]; then
echo ============================================================================
echo "          Train mono system                                               "
echo ============================================================================
  utils/subset_data_dir.sh $data/$code/train \
                           10000 \
                           $data/$code/train.10K || error "Failed"

  steps/train_mono.sh --nj $num_jobs \
                      --cmd "$train_cmd" \
                      $data/samromur/train.10K \
                      $data/$code/lang \
                      $exp/$code/mono || error "Failed"
fi

if [ $stage -le 5 ]; then
  echo ============================================================================
  echo "          Train tri1 delta+deltadelta system                               "
  echo ============================================================================
  echo "$0: Aligning data using monophone system"
  steps/align_si.sh --nj $num_jobs \
                    --cmd "$train_cmd" \
                    $data/$code/train \
                    $data/$code/lang \
                    $exp/$code/mono \
                    $exp/$code/mono_ali || exit 1;

  echo "$0: training triphone system with delta features"
  steps/train_deltas.sh --cmd "$train_cmd" \
                        2500 30000 \
                        $data/$code/train \
                        $data/$code/lang \
                        $exp/$code/mono_ali \
                        $exp/$code/tri1 || exit 1;
fi

if [ $stage -le 6 ]; then
  echo ============================================================================
  echo "     Train tri2 aligning data and retraining and realigning with lda_mllt   "
  echo ============================================================================
  steps/align_si.sh --nj $num_jobs \
                    --cmd "$train_cmd" \
                    $data/$code/train \
                    $data/$code/lang \
                    $exp/$code/tri1 \
                    $exp/$code/tri1_ali || exit 1;

  steps/train_lda_mllt.sh --cmd "$train_cmd" \
                          4000 50000 \
                          $data/$code/train \
                          $data/$code/lang \
                          $exp/$code/tri1_ali \
                          $exp/$code/tri2b || exit 1;
fi

if [ $stage -le 7 ]; then
  echo ============================================================================
  echo "          Train tri3 LDA+MLLT+SAT system                                  "
  echo ============================================================================
  echo "$0: Aligning data and retraining and realigning with sat_basis"
  steps/align_si.sh --nj $num_jobs \
                    --cmd "$train_cmd" \
                    $data/$code/train \
                    $data/$code/lang \
                    $exp/$code/tri2b \
                    $exp/$code/tri2b_ali || exit 1;

  steps/train_sat_basis.sh --cmd "$train_cmd" \
                           5000 100000 \
                           $data/$code/train \
                           $data/$code/lang \
                           $exp/$code/tri2b_ali \
                           $exp/$code/tri3b || exit 1;

  steps/align_fmllr.sh --nj $num_jobs \
                        --cmd "$train_cmd" \
                        $data/$code/train \
                        $data/$code/lang \
                        $exp/$code/tri3b \
                        $exp/$code/tri3b_ali || exit 1;
fi

if [ $stage -le 8 ]; then
  echo ============================================================================
  echo "          Decoding tri3                          "
  echo ============================================================================
  tri=tri3b
  utils/mkgraph.sh $decode_lm \
                   $exp/$code/$tri \
                   $exp/$code/$tri/graph || exit 1;

  for dir in dev test; do
    (
    steps/decode_fmllr.sh --nj $num_decode_jobs \
                          --cmd "$decode_cmd" \
                          $exp/$code/$tri/graph \
                          $data/$code/$dir \
                          $exp/$code/$tri/decode_${dir}

    steps/lmrescore_const_arpa.sh --cmd "$decode_cmd" \
                                  $decode_lm \
                                  $rescore_lm \
                                  $data/$code/$dir \
                                  $exp/$code/$tri/decode_$dir \
                                  $exp/$code/$tri/decode_${dir}
    ) &
  done
  wait
  
  # WER info:
  for x in $exp/$code/*/decode_{test,dev}_rescored_rescored_better_model; do
    [ -d "$x" ] && grep WER "$x"/wer_* | utils/best_wer.sh;
  done > RESULTS
fi



s5/local/data_prep.sh \
  $libre_data/train-clean-360 \
  $data/train_clean_360

steps/make_mfcc.sh \
  --cmd "$train_cmd" \
  --nj 40 \
  $data/$code/train_clean_360 \
  $exp/$code/make_mfcc/train_clean_360 \
  $mfcc_dir

steps/compute_cmvn_stats.sh \
  $data/$code/train_clean_360 \
  $exp/$code/make_mfcc/train_clean_360 \
  $mfcc_dir

# ... and then combine the two sets into a 460 hour one
utils/combine_data.sh \
  $data/$code/train_clean_460 \
  $data/$code/train_clean_100 \
  $data/$code/train_clean_360

# align the new, combined set, using the tri4b model
steps/align_fmllr.sh --nj 40 --cmd "$train_cmd" \
                      $data/$code/train_clean_460 \
                      $data/$code/lang \
                      $exp/$code/tri4b \
                      $exp/$code/tri4b_ali_clean_460

# create a larger SAT model, trained on the 460 hours of data.
steps/train_sat.sh  --cmd "$train_cmd" 5000 100000 \
                    $data/$code/train_clean_460 \
                    $data/$code/lang \
                    $exp/$code/tri4b_ali_clean_460 
                    $exp/$code/tri5b



if [ $stage -le 9 ] && $tdnn; then
    affix="_${lang}"
    rescore_lm="/home/derik/work/samromur-asr/s5_subwords/data/lm_ice/lang_10g"
    decode_lm=/home/derik/work/samromur-asr/s5_subwords/data/lm_ice/lang_6g
    nohup local/chain/run_tdnn.sh --stage 15 \
                            --affix $affix \
                            --decoding-lang $decode_lm \
                            --rescoring-lang $rescore_lm \
                            --langdir $data/$code/lang \
                            --gmm $code/tri3b \
                            $data/$code/train \
                            $data/$code/ \
                            $code \
                            >> logs/tdnn$affix.log 2>&1 &
    
    
    for x in $exp/chain/tdnn${affix}_sp/decode*; do 
    
      [ -d $x ] && grep WER $x/wer_* | utils/best_wer.sh; 
    
    done >> RESULTS
    
fi


echo "$0: training succeeded"
exit 0