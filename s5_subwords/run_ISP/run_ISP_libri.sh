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
create_mfcc=true


libri_data=/work/derik/librispeech/LibriSpeech
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
  for part in dev-clean test-clean dev-other test-other train-clean-100 train-clean-360 train-other-500; do
    local/libri/data_prep.sh $libri_data/$part $data/$code/$(echo $part | sed s/-/_/g)
  done
fi

if [ $stage -le 1 ]; then
echo ============================================================================
echo "               Create $method model and preparing text files         "
echo ============================================================================

  python3 local/sw_methods/bpe/learn_bpe.py -i $text_corpus \
                                            -s $sw_count > $subword_dir/pair_codes

  for x in dev_clean test_clean dev_other test_other train_clean_100 train_clean_360 train_other_500; do
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
  num_jobs=50

  for x in dev_clean test_clean dev_other test_other train_clean_100 train_clean_360 train_other_500; do
    steps/make_mfcc.sh --cmd "$train_cmd" \
                       --nj $num_jobs \
                       $data/$code/$x \
                       $mfcc_dir/log/make_mfcc \
                       $mfcc_dir/$x 

    steps/compute_cmvn_stats.sh $data/$code/$x \
                                $exp/$code/mfcc/log/cmvn_stats \
                                $mfcc_dir/$x 
    
    utils/validate_data_dir.sh $data/$code/$x || utils/fix_data_dir.sh $data/$code/$x 
  done
fi


echo ===========================================================================
echo "                		create subesets			                "
echo ============================================================================
  # Lets create the subsets 
  # 10h	20h	40h	80h	160h	320h	640h
  # The average length of a clip is 12.688
  # 2837	5674	11349	22697	45394	90788	181577

  # Actual:
  # 10h:10.0163h:2820
  # 20h:20.0041h:5680
  # 40h:40.0553h:11380
  # 80h:79.9885h:22690
  # 160h:159.953h:16986
  # 320h:319.996h:62761
  # 640h:640.38h:52747


  # We start by just using the train_clean_100 subset and create smaller subset from it
  x=10
  clips=2820
  utils/subset_data_dir.sh $data/libri/train_clean_100 $clips $data/libri_train_${x}h
  a=$(cut -d" " -f2  $data/libri_train_${x}h/utt2dur | awk '{s+=$1} END {print s/3600}')
  echo "${x}h:${a}h:${clips}" >> log

  x=20
  clips=5680
  utils/subset_data_dir.sh $data/libri/train_clean_100 $clips $data/libri_train_${x}h
  a=$(cut -d" " -f2  $data/libri_train_${x}h/utt2dur | awk '{s+=$1} END {print s/3600}')
  echo "${x}h:${a}h:${clips}" >> log

  x=40
  clips=11380
  utils/subset_data_dir.sh $data/libri/train_clean_100 $clips $data/libri_train_${x}h
  a=$(cut -d" " -f2  $data/libri_train_${x}h/utt2dur | awk '{s+=$1} END {print s/3600}')
  echo "${x}h:${a}h:${clips}" >> log

  x=80
  clips=22690
  utils/subset_data_dir.sh $data/libri/train_clean_100 $clips $data/libri_train_${x}h
  a=$(cut -d" " -f2  $data/libri_train_${x}h/utt2dur | awk '{s+=$1} END {print s/3600}')
  echo "${x}h:${a}h:${clips}" >> log

  # We now need to take from train_clean_360 as well. The total number of clips in train_clean_100
  # are 28539
  x=160
  clips_in_clean_100=28539
  clips=$(( 45525 - $clips_in_clean_100))
  echo $clips
  utils/subset_data_dir.sh $data/libri/train_clean_360 $clips $data/tmp
  utils/combine_data.sh $data/libri_train_${x}h $data/tmp $data/libri/train_clean_100
  rm -r $data/tmp
  a=$(cut -d" " -f2  $data/libri_train_${x}h/utt2dur | awk '{s+=$1} END {print s/3600}')
  echo "${x}h:${a}h:${clips}" >> log

  x=320
  clips_in_clean_100=28539
  clips=$(( 91300 - $clips_in_clean_100))
  echo $clips
  utils/subset_data_dir.sh $data/libri/train_clean_360 $clips $data/tmp
  utils/combine_data.sh $data/libri_train_${x}h $data/tmp $data/libri/train_clean_100
  rm -r $data/tmp
  a=$(cut -d" " -f2  $data/libri_train_${x}h/utt2dur | awk '{s+=$1} END {print s/3600}')
  echo "${x}h:${a}h:${clips}" >> log

  # We now need to take from train_other_500 as well. The total number of clips in train_clean_360
  # are 104014

  x=640
  clips_in_clean_100=28539
  clips_in_clean_360=104014
  clips=$(( 185300 - $clips_in_clean_100 - $clips_in_clean_360))
  echo $clips
  utils/subset_data_dir.sh $data/libri/train_other_500 $clips $data/tmp
  utils/combine_data.sh $data/libri_train_${x}h $data/tmp $data/libri/train_clean_100 $data/libri/train_clean_360
  rm -r $data/tmp
  a=$(cut -d" " -f2  $data/libri_train_${x}h/utt2dur | awk '{s+=$1} END {print s/3600}')
  echo "${x}h:${a}h:${clips}" >> log



echo ============================================================================
echo "          Train mono system                                               "
echo ============================================================================

  for x in 10h 20h 40h 80h 160h 320h 640h; do
    utils/fix_data_dir.sh $data/${code}_train_${x}
  done
  # If there are no errors then we can train the monophone model

  # There are only 2820 and 5680 utterances in the 10h and 20h
  for x in 40h 80h 160h 320h 640h; do
        utils/subset_data_dir.sh $data/${code}_train_${x} \
                                10000 \
                                $data/${code}_train_${x}/train.10K
  done

  for x in 10h 20h ; do
    (
    steps/train_mono.sh --nj $num_jobs --cmd "$train_cmd" \
                    $data/${code}_train_${x} \
                    $data/${code}/lang \
                    $exp/$code/${x}/mono 
    ) >> logs/${code}/${x}.log 2>&1 &
  done

  for x in 40h 80h 160h 320h 640h; do
        (
        steps/train_mono.sh --nj $num_jobs --cmd "$train_cmd" \
                        $data/${code}_train_${x}/train.10K \
                        $data/${code}/lang \
                        $exp/$code/${x}/mono \
                         
        ) >> logs/${code}/${x}.log 2>&1 &
  done

echo ============================================================================
echo "          Train tri1 delta+deltadelta system                               "
echo ============================================================================
echo "$0: Aligning data using monophone system" 
for x in 160h 320h 640h; do
  (
  steps/align_si.sh --nj $num_jobs \
                    --cmd "$train_cmd" \
                    $data/${code}_train_${x} \
                    $data/$code/lang \
                    $exp/$code/$x/mono \
                    $exp/$code/$x/mono_ali 
                    
  
  echo "$0: training triphone system with delta features"
  steps/train_deltas.sh --cmd "$train_cmd" \
                        2500 30000 \
                        $data/${code}_train_${x} \
                        $data/$code/lang \
                        $exp/$code/$x/mono_ali \
                        $exp/$code/$x/tri1

  ) >> logs/${code}/${x}.log 2>&1  &
done
wait
  
echo ============================================================================
echo "     Train tri2 aligning data and retraining and realigning with lda_mllt   "
echo ============================================================================
for x in 10h 20h 40h 80h 160h 320h 640h; do
  (
    steps/align_si.sh --nj $num_jobs \
                      --cmd "$train_cmd" \
                      $data/${code}_train_${x} \
                      $data/$code/lang \
                      $exp/$code/$x/tri1 \
                      $exp/$code/$x/tri1_ali 
                      
    steps/train_lda_mllt.sh --cmd "$train_cmd" \
                            4000 50000 \
                            $data/${code}_train_${x} \
                            $data/$code/lang \
                            $exp/$code/$x/tri1_ali \
                            $exp/$code/$x/tri2b 

  ) >> logs/${code}/${x}.log 2>&1 
done
wait

echo ============================================================================
echo "          Train tri3 LDA+MLLT+SAT system                                  "
echo ============================================================================

for x in 10h 20h 40h 80h 160h 320h 640h; do
  (
    echo "$0: Aligning data and retraining and realigning with sat_basis"
    steps/align_si.sh --nj $num_jobs \
                      --cmd "$train_cmd" \
                      $data/${code}_train_${x} \
                      $data/$code/lang \
                      $exp/$code/$x/tri2b \
                      $exp/$code/$x/tri2b_ali

    steps/train_sat_basis.sh --cmd "$train_cmd" \
                              5000 100000 \
                              $data/${code}_train_${x} \
                              $data/$code/lang \
                              $exp/$code/$x/tri2b_ali \
                              $exp/$code/$x/tri3b 

    steps/align_fmllr.sh --nj $num_jobs \
                          --cmd "$train_cmd" \
                            $data/${code}_train_${x} \
                          $data/$code/lang \
                          $exp/$code/$x/tri3b \
                          $exp/$code/$x/tri3b_ali 
                          
  ) >> logs/${code}/${x}.log 2>&1
done


echo ============================================================================
echo "          Decoding tri3                          "
echo ============================================================================

for x in 10h ; do
  (
  nohup utils/mkgraph.sh $decode_lm \
                         $exp/$code/$x/tri3b \
                         $exp/$code/$x/tri3b/graph 
  ) >> logs/${code}/${x}.log  2>&1 
done


# We are using the samrómur test and dev set as well as the althingi test
# and dev sets. 
for x in 10h; do
  for set in dev_clean test_clean; do
    (
    steps/decode_fmllr.sh --nj $num_decode_jobs \
                          --cmd "$decode_cmd" \
                          $exp/$code/$x/tri3b/graph \
                          $data/$code/$set \
                          $exp/$code/$x/tri3b/decode_${set}

    steps/lmrescore_const_arpa.sh --cmd "$decode_cmd" \
                                  $decode_lm \
                                  $rescore_lm \
                                  $data/$code/$set \
                                  $exp/$code/$x/tri3b/decode_${set} \
                                  $exp/$code/$x/tri3b/decode_${set}_rescored
    ) >> logs/${code}/${x}.log  2>&1
    done
done


# 
# -----------------------------Let train the time delay neural network!-----------------------------

for x in 320h 640h; do
    run_ISP/run_tdnn_ISP.sh --stage 6 \
                            --affix $x \
                            --decoding-lang $decode_lm \
                            --rescoring-lang $rescore_lm \
                            --langdir $data/$code/lang \
                            --data $data/${code}_train_${x}\
                            --exp $exp/$code/$x \
                            $data/${code}_train_${x} \
                            $data/$code \
                            >> logs/$code/${x}_tdnn.log 2>&1
done