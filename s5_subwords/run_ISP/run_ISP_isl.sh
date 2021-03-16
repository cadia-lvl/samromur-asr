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
code=isl
method='bpe'
sw_count=3000

#METADATA=/home/derik/work/tools/normalize/malromur/normalized_files/malromur_metadata_subset.tsv # A small subest of the corpus, used for fast testing.

# Text corpus for the LM
# text_corpus=/data/asr/malromur/malromur2017/malromur_corpus.txt
#text_corpus=/work/derik/language_models/LM_corpus/rmh_test
text_corpus=/work/derik/language_models/LM_corpus/rmh_2020-11-23_shuffle+malromur.txt

samromur_root=/data/asr/samromur/samromur_ldc

# Todo: Sanity check

decode_lm=/home/derik/work/samromur-asr/s5_subwords/data_ISP/isl_lm/lang_6g
rescore_lm=/home/derik/work/samromur-asr/s5_subwords/data_ISP/isl_lm/lang_8g

data=data_ISP
exp=exp_ISP

subword_dir=$data/isl_sw_bpe_3000
mkdir -p $subword_dir

. utils/parse_options.sh || exit 1;
. path.sh
. cmd.sh 


if [ $stage -le 0 ]; then
  echo ============================================================================
  echo "                		Data Prep			                "
  echo ============================================================================
    local/malromur_prep_data.py -a $MALROMUR_AUDIO \
                                -m $METADATA \
                                -o $data/tmp_malromur 

    local/samromur_prep_data.py -a $samromur_root/audio \
                                -m $samromur_root/metadata.tsv \
                                -o $data/tmp_samromur

    # Here we add all the malromur data as training data as they are very similar corpora, but keeping the defined dev and test from samrómur
    #
    utils/combine_data.sh $data/$code/train $data/tmp_malromur/train $data/tmp_samromur/train $data/tmp_malromur/test $data/tmp_malromur/dev
    utils/combine_data.sh $data/$code/test $data/tmp_samromur/test
    utils/combine_data.sh $data/$code/dev $data/tmp_samromur/dev
    rm -r $data/tmp_malromur $data/tmp_samromur
  
  # We then copy the althingi data folders from /data/asr/althingi/data/acoustic_model/20181218
  # That corpus contains 1200h of data, which is more than we need. We start by creating a subset 
  # of half of the training data called train_600h. We used the parameter --speakers whichi randomly
  #  selects enough speakers that we have <num-utt> utterances

  code='althingi'
  x=600
  utils/subset_data_dir.sh --speakers $data/$code/train/ 388700 $data/$code/train_${x}h
  cut -d" " -f2 $data/$code/train_${x}h/utt2dur | awk '{s+=$1} END {print s/3600}' 

  # Then we create the pair codes used for subword tokenization. 

    python3 local/sw_methods/bpe/learn_bpe.py -i $text_corpus \
                                                -s $sw_count > $subword_dir/pair_codes
      
    # Using the pair_codes we subword tokenize the kaldi format text files
    # We change this for loop and the $code we working with the different corpora.
    # code='althingi'/'sm'

    # the althingi training data is segmented from long audio files and the <unk> is 
    # added at some segmetnation points. 

    for x in train_600h dev test; do
      #echo "$0: Applying BPE to $x"
      ./local/sw_methods/bpe/prepare_subword_text.sh --glossaries "<unk>" \
                                                    $data/$code/${x}/text \
                                                    $subword_dir/pair_codes \
                                                    $data/$code/${x}/text.seg \
                                                    || error "Failed applying BPE"                                                     
    done
      
    # Tokenize the text corpus that will be used for language model training
    python3 local/sw_methods/bpe/apply_bpe.py -i $text_corpus \
                                              --codes $subword_dir/pair_codes \
                                              | sort -u > $subword_dir/text_corpus
    
    
    # Lets create the lang and dict directory using the subword tokenized text corpus
    echo "$0: Preparing lexicon, dict folder and lang folder" 
    local/prepare_dict_subword.sh $subword_dir/text_corpus \
                                  $subword_dir \
                                  $data/isl_local/dict \
                                  || error "Failed preparing lang"

    utils/subword/prepare_lang_subword.sh $data/isl_local/dict \
                                          "<UNK>" \
                                          $data/isl_local/lang \
                                          $data/isl_lang \
                                          || error "Failed preparing lang"


  echo ===========================================================================
  echo "                		Creating MFCC			                "
  echo ============================================================================
    # Next we extract the MfCC's and compute the cmvn stats from sm and the althingi
    # train_600h and the test and dev sets.
    for code in althingi; do
      mfcc_dir=$exp/$code/mfcc
      for x in dev test; do
        steps/make_mfcc.sh --cmd "$train_cmd" \
                          --nj $num_jobs \
                          $data/$code/$x \
                          $mfcc_dir/log/make_mfcc \
                          $mfcc_dir/$x 

        steps/compute_cmvn_stats.sh $data/$code/$x \
                                    exp/$code/mfcc/log/cmvn_stats \
                                    $mfcc_dir/$x 
        
        utils/validate_data_dir.sh $data/$code/$x || utils/fix_data_dir.sh $data/$code/$x 
      done
    done


  echo ============================================================================
  echo "                		Prepare LM with subword text files with $method          "
  echo ============================================================================
      # We create two language model  
      # One for decoding kenlm 6g, pruning: 0 2 5 10, bpe3000, arpa
      # Another for rescoring kenlm 10g, pruning: 0 2, bpe3000, carpa
     
      lm_order=6
      echo "Preparing an ${lm_order}g LM"
      $train_cmd --mem 80G "logs/$code/lm/make_LM_${lm_order}g_pruned.log" \
                local/lm/make_LM.sh \
                --order $lm_order \
                --pruning "0 2 5 10" \
                --carpa false \
                $subword_dir/text_corpus \
                $data/${code}_lang \
                $data/${code}_local/dict/lexicon.txt \
                $data/lm_ice \
                "${method}${sw_count}_pruned" \
                || error 1 "Failed creating an pruned ${lm_order}g LM";

      echo "Done creating an ${lm_order}g. The log is available logs/make_LM_${lm_order}g.log"
    
      # Creating an minimum pruned lm for rescoring
      lm_order=8
      echo "Preparing an ${lm_order}g LM"
      $train_cmd --mem 80G "logs/$code/lm/make_LM_${lm_order}g.log" \
                local/lm/make_LM.sh \
                --order $lm_order \
                --pruning "0 2" \
                --carpa true \
                $subword_dir/text_corpus \
                $data/${code}_lang \
                $data/${code}_local/dict/lexicon.txt \
                $data/lm_ice \
                "${method}${sw_count}" \
                || error 1 "Failed creating an pruned ${lm_order}g LM";

      echo "Done creating an ${lm_order}g. The log is available logs/make_LM_${lm_order}g.log"
    

  # Let's now create the subsets of the accustic data. We will call the icelandic training data isl_train_{x}h
  # and the libri speech data libri_train_{x}h. Where x is one of 10	20	40	80	160	320	640. 

  # For the isl data we try to make the subest constitute of 1/3 althingi data and 2/3 sm (samromur+malromur). 

  # Estimation of clips needed
  #         Average duration of clips
  # SM	    4.790565926
  # Alþingi	5.479478583
  # Hours             10	  20	  40	  80	  160	  320	    640
  # SM      2/3	0.66	4960	9919	19839	39678	79356	158712	297585
  # Alþingi 1/3	0.33	2168	4336	8672	17345	34689	69379	  130085

  # We did rough estimates of clips needed from each corpus with spreadsheet using the average length of utterances
  # in each corpus. 

  # The data is split as the following:

  # hours:actual:#clips_sm:#clips_althingi
  # 10h:10.0243h:5000:2200
  # 20h:20.0156h:9950:4400
  # 40h:40.029h:20000:8700
  # 80h:80.003h:39750:17450
  # 160h:160.066h:79600:34900
  # 320h:320.022h:159400:69800
  # 640h:640.101h:185858:254000

  x=10
  sm_clips=5000
  althingi=2200
  utils/subset_data_dir.sh $data/althingi/train_600h $althingi $data/tmp_althingi_${x}h
  utils/subset_data_dir.sh $data/sm/train $sm_clips $data/tmp_sm_${x}h
  utils/combine_data.sh $data/isl_train_${x}h $data/tmp_althingi_${x}h $data/tmp_sm_${x}h
  a=$(cut -d" " -f2  $data/isl_train_${x}h/utt2dur | awk '{s+=$1} END {print s/3600}')
  rm -r $data/tmp_althingi_${x}h  $data/tmp_sm_${x}h
  echo "${x}h:${a}h:${sm_clips}:${althingi}">> log

  x=20
  sm_clips=9950
  althingi=4400
  utils/subset_data_dir.sh $data/althingi/train_600h $althingi $data/tmp_althingi_${x}h
  utils/subset_data_dir.sh $data/sm/train $sm_clips $data/tmp_sm_${x}h
  utils/combine_data.sh $data/isl_train_${x}h $data/tmp_althingi_${x}h $data/tmp_sm_${x}h
  a=$(cut -d" " -f2  $data/isl_train_${x}h/utt2dur | awk '{s+=$1} END {print s/3600}')
  rm -r $data/tmp_althingi_${x}h  $data/tmp_sm_${x}h
  echo "${x}h:${a}h:${sm_clips}:${althingi}">> log

  x=40
  sm_clips=20000
  althingi=8700
  utils/subset_data_dir.sh $data/althingi/train_600h $althingi $data/tmp_althingi_${x}h
  utils/subset_data_dir.sh $data/sm/train $sm_clips $data/tmp_sm_${x}h
  utils/combine_data.sh $data/isl_train_${x}h $data/tmp_althingi_${x}h $data/tmp_sm_${x}h
  a=$(cut -d" " -f2  $data/isl_train_${x}h/utt2dur | awk '{s+=$1} END {print s/3600}')
  rm -r $data/tmp_althingi_${x}h  $data/tmp_sm_${x}h
  echo "${x}h:${a}h:${sm_clips}:${althingi}">> log


  x=80
  sm_clips=39750
  althingi=17450
  utils/subset_data_dir.sh $data/althingi/train_600h $althingi $data/tmp_althingi_${x}h
  utils/subset_data_dir.sh $data/sm/train $sm_clips $data/tmp_sm_${x}h
  utils/combine_data.sh $data/isl_train_${x}h $data/tmp_althingi_${x}h $data/tmp_sm_${x}h
  a=$(cut -d" " -f2  $data/isl_train_${x}h/utt2dur | awk '{s+=$1} END {print s/3600}')
  rm -r $data/tmp_althingi_${x}h  $data/tmp_sm_${x}h
  echo "${x}h:${a}h:${sm_clips}:${althingi}">> log

  x=160
  sm_clips=79600
  althingi=34900
  utils/subset_data_dir.sh $data/althingi/train_600h $althingi $data/tmp_althingi_${x}h
  utils/subset_data_dir.sh $data/sm/train $sm_clips $data/tmp_sm_${x}h
  utils/combine_data.sh $data/isl_train_${x}h $data/tmp_althingi_${x}h $data/tmp_sm_${x}h
  a=$(cut -d" " -f2  $data/isl_train_${x}h/utt2dur | awk '{s+=$1} END {print s/3600}')
  rm -r $data/tmp_althingi_${x}h  $data/tmp_sm_${x}h
  echo "${x}h:${a}h:${sm_clips}:${althingi}">> log


  x=320
  sm_clips=159400
  althingi=69800
  utils/subset_data_dir.sh $data/althingi/train_600h $althingi $data/tmp_althingi_${x}h
  utils/subset_data_dir.sh $data/sm/train $sm_clips $data/tmp_sm_${x}h
  utils/combine_data.sh $data/isl_train_${x}h $data/tmp_althingi_${x}h $data/tmp_sm_${x}h
  a=$(cut -d" " -f2  $data/isl_train_${x}h/utt2dur | awk '{s+=$1} END {print s/3600}')
  rm -r $data/tmp_althingi_${x}h  $data/tmp_sm_${x}h
  echo "${x}h:${a}h:${sm_clips}:${althingi}">> log

  # There are 185858 clips in sm so we now sample more from althingi corpus for 
  # the following set

  x=640
  sm_clips=185858
  althingi=254000
  utils/subset_data_dir.sh $data/althingi/train_600h $althingi $data/tmp_althingi_${x}h
  utils/subset_data_dir.sh $data/sm/train $sm_clips $data/tmp_sm_${x}h
  utils/combine_data.sh $data/isl_train_${x}h $data/tmp_althingi_${x}h $data/tmp_sm_${x}h
  a=$(cut -d" " -f2  $data/isl_train_${x}h/utt2dur | awk '{s+=$1} END {print s/3600}')
  rm -r $data/tmp_althingi_${x}h  $data/tmp_sm_${x}h
  echo "${x}h:${a}h:${sm_clips}:${althingi}" >> log

  echo ============================================================================
  echo "          Train mono system                                               "
  echo ============================================================================
  # Lets now create a monophone system
  # We start by taking 10k utterances subset for faster training. 
  # We don't do that for the smallest coprora as it has less then 
  # 10k utternaces
  for x in 10h 20h 40h 80h 160h 320h 640h; do
    utils/fix_data_dir.sh $data/${code}_train_${x}
  done
  # We lose about 21 clips for some reason for isl_train_10h 

  for x in 20h 40h 80h 160h 320h 640h; do
        utils/subset_data_dir.sh $data/${code}_train_${x} \
                                10000 \
                                $data/${code}_train_${x}/train.10K
  done

  steps/train_mono.sh --nj $num_jobs --cmd "$train_cmd" \
                  $data/isl_train_10h \
                  $data/${code}_lang \
                  $exp/$code/${x}/mono 

  for x in 20h 40h 80h 160h 320h 640h; do
        (
        steps/train_mono.sh --nj $num_jobs --cmd "$train_cmd" \
                        $data/${code}_train_${x}/train.10K \
                        $data/${code}_lang \
                        $exp/$code/${x}/mono \
                        >> logs/${code}/${x}.log 2>&1 
        ) &
  done
  wait
fi

if [ $stage -le 1 ]; then
  echo ============================================================================
  echo "          Train tri1 delta+deltadelta system                               "
  echo ============================================================================
  echo "$0: Aligning data using monophone system" 
  for x in 10h 20h 40h 80h 160h 320h 640h; do
    (
    steps/align_si.sh --nj $num_jobs \
                      --cmd "$train_cmd" \
                      $data/${code}_train_${x} \
                      $data/${code}_lang \
                      $exp/$code/$x/mono \
                      $exp/$code/$x/mono_ali 
                      
    
    echo "$0: training triphone system with delta features"
    steps/train_deltas.sh --cmd "$train_cmd" \
                          2500 30000 \
                          $data/${code}_train_${x} \
                          $data/${code}_lang \
                          $exp/$code/$x/mono_ali \
                          $exp/$code/$x/tri1

    ) >> logs/${code}/${x}.log 2>&1 
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
                        $data/${code}_lang \
                        $exp/$code/$x/tri1 \
                        $exp/$code/$x/tri1_ali 
                        
      steps/train_lda_mllt.sh --cmd "$train_cmd" \
                              4000 50000 \
                              $data/${code}_train_${x} \
                              $data/${code}_lang \
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
                        $data/${code}_lang \
                        $exp/$code/$x/tri2b \
                        $exp/$code/$x/tri2b_ali

      steps/train_sat_basis.sh --cmd "$train_cmd" \
                                5000 100000 \
                                $data/${code}_train_${x} \
                                $data/${code}_lang \
                                $exp/$code/$x/tri2b_ali \
                                $exp/$code/$x/tri3b 

      steps/align_fmllr.sh --nj $num_jobs \
                            --cmd "$train_cmd" \
                             $data/${code}_train_${x} \
                            $data/${code}_lang \
                            $exp/$code/$x/tri3b \
                            $exp/$code/$x/tri3b_ali 
                            
    ) >> logs/${code}/${x}.log 2>&1 
  done
fi

echo ============================================================================
echo "          Decoding tri3                          "
echo ============================================================================

for x in 10h 20h 40h 80h 160h 320h 640h; do
  (
  nohup utils/mkgraph.sh $decode_lm \
                   $exp/$code/$x/tri3b \
                   $exp/$code/$x/tri3b/graph 
  ) >> logs/${code}/${x}.log  2>&1 
done


# We are using the samrómur test and dev set as well as the althingi test
# and dev sets. 
for x in 10h; do
  for set in sm_dev sm_test althingi_dev althingi_test; do
    (
    steps/decode_fmllr.sh --nj $num_decode_jobs \
                          --cmd "$decode_cmd" \
                          $exp/$code/$x/tri3b/graph \
                          $data/sm/$set \
                          $exp/$code/$x/tri3b/decode_${set}

    steps/lmrescore_const_arpa.sh --cmd "$decode_cmd" \
                                  $decode_lm \
                                  $rescore_lm \
                                  $data/sm/$set \
                                  $exp/$code/$x/tri3b/decode_${set} \
                                  $exp/$code/$x/tri3b/decode_${set}_rescored
    ) >> logs/${code}/${x}_decode.log  2>&1
    done
done

  # WER info:
for x in 10h 20h 40h 80h 160h 320h 640h; do
  echo $x
  for i in $exp/$code/$x/*/decode_{test,dev}_rescored $exp/$code/$x/*/decode_{test,dev}; do
    [ -d "$i" ] && grep WER "$i"/wer_* | utils/best_wer.sh;
  echo 
  done 
done >> results/$code/RESULTS


# 
# -----------------------------Let train the time delay neural network!-----------------------------

for x in 40h 80h 160h; do
    run_ISP/run_tdnn_ISP.sh --stage 5 \
                            --affix $x \
                            --decoding-lang $decode_lm \
                            --rescoring-lang $rescore_lm \
                            --langdir $data/${code}_lang \
                            --data $data/${code}_train_${x} --exp $exp/$code/$x \
                            $data/${code}_train_${x} \
                            $data/sm \
                            >> logs/$code/${x}_tdnn.log 2>&1
    
done