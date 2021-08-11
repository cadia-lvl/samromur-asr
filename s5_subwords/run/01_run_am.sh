#!/usr/bin/env bash

export LC_ALL=C

num_jobs=50
stage=4

. ./cmd.sh
. ./path.sh
./setup.sh
. utils/parse_options.sh

language=isl
root_data_dir=/scratch/derik/subword_journal

data=$root_data_dir/$language/data
exp=$root_data_dir/$language/exp
log=logs/isl

mkdir -p $data $exp $log

if [ $stage -le 0 ]; then
  echo ============================================================================
  echo "                		Data prep			                              "
  echo ============================================================================
  if [ $language == 'isl' ]; then
    # Convert the Samrómur corpus metadata to the Kaldi data format
    ./local/samromur_prep_data.py --a /data/asr/samromur/r1/ \
      --m /data/asr/samromur/r1/metadata.tsv  \
      --o $data/samromur 

    # Convert the Málrómur corpus metadata to the Kaldi data format   
    ./local/malromur_prep_data.py -a /data/asr/malromur/malromur2017/correct \
      -m /data/asr/malromur/malromur2017/malromur_metadata.tsv  \
      -o $data/malromur 
  
    # The Althingi corpus has the Kaldi format included but the folders the
    # test folder has another naming convention. 
    cp -r /data/asr/althingi/LDC2021S01/data/malfong $data/althingi 
    mv $data/althingi/eval $data/althingi/test 
    
    # We don't need the LM's that are provieded. 
    rm -r $data/althingi/{lang_3gsmall,lang_5glarge}

    # We need to create the wav.scp file for the althingi set
    for x in train test dev; do 
      ./local/althingi_prep_data.py $data/althingi/$x/reco2audio \
        /data/asr/althingi/LDC2021S01/data/audio \
        > $data/althingi/$x/wav.scp 
    done
  fi 

  if [ $language == 'eng' ]; then
    #ToDo
    echo ToDo
  fi 

  if [ $language == 'es' ]; then
    #ToDo
    echo ToDo
  fi 

fi

if [ $stage -le 1 ]; then
  echo ============================================================================
  echo "       		Creating MFCC and computing cmvn stats                        "
  echo ============================================================================
  if [ $language == 'isl' ]; then
    for set in althingi malromur samromur; do
      for x in train dev test; do
      printf "\n$set - $x\n"
        steps/make_mfcc.sh --cmd "$train_cmd" \
          --nj $num_jobs \
          $data/$set/$x \
          $log/mfcc/$set/log_${x} \
          $exp/mfcc/$set/$x 

        steps/compute_cmvn_stats.sh $data/$set/$x \
          $log/mfcc/$set/log_${x}  \
          $exp/mfcc/$set/$x 
        
        utils/validate_data_dir.sh $data/$set/$x || utils/fix_data_dir.sh $data/$set/$x 
      done
    done
    
    # Lets combine all training datasets to a singal folder. Note, we are lucky that no utterance 
    # id's are the same across datasets. This might not be true for all the languages. 
    for x in train; do 
      mkdir -p $data/combined/$x
      ./utils/combine_data.sh $data/combined/$x $data/samromur/$x $data/malromur/$x $data/althingi/$x
    done
  fi

  if [ $language == 'eng' ]; then
    #ToDo
    echo ToDo
  fi 

  if [ $language == 'es' ]; then
    #ToDo
    echo ToDo
  fi

fi

if [ $stage -le 2 ]; then
  echo ============================================================================
  echo "           	Preparing lexicon, dict folder and lang folder             "
  echo ============================================================================
  if [ $language == 'isl' ]; then

  # I add the text from train, dev and test to the lm corpus. 
  # Adding all the text from the training, dev, test to the text corpus.
  # Modify the following commands for your set up. 
  
  # for x in $data/{samromur,althingi,malromur}/{train,dev,test}/text; do 
  # 	cut -d" " -f2- $x >> $data/../text_corpora/rmh_2020-11-23+sm+malromur+althingi
  # done 
  
  # sort -u text_corpora/rmh_2020-11-23+sm+malromur+althingi > text_corpora/rmh_2020-11-23+sm+malromur+althingi_sorted 
 
  # Removing the unsorted corpus to save space.
  # rm text_corpora/rmh_2020-11-23+sm+malromur+althingi
  
  # I ran local/prepare_dict.sh and found in data/dict_grapheme/base/nonsilence_phones.txt that their where some non icelandic characters in the text.
  # And not all charachters where lower case, converted all text to lower case.
  # for x in $data/{samromur,malromur,althingi}/{train,dev,test}; do
  #   cat $x/text | ./local/to_lower.py > $x/text_new  
  #   mv $x/text_new $x/text
  # done


  # Did the following cleanup and ran again
  # sed 's/.*[çøäåëüq05].*//g' rmh_2020-11-23+sm+malromur+althingi_sorted | sed 's/<unk>//g' | sed -r '/^\s*$/d' > rmh_2020-11-23+sm+malromur+althingi_sorted_cleaned
 
  # Saving a few stats the might become interesting 
  # rmh_2020-11-23 								                      44.049.610
  # rmh_2020-11-23+sm+malromur+althingi 		            44.465.931
  # rmh_2020-11-23+sm+malromur+althingi_sorted          44.288.307
  # rmh_2020-11-23+sm+malromur+althingi_sorted_cleaned  44.225.989
  TEXT_CORPUS=$data/../text_corpora/rmh_2020-11-23+sm+malromur+althingi_sorted_cleaned
  
  local/prepare_dict.sh $TEXT_CORPUS \
    $data/local_grapheme/tmp/base \
    $data/dict_grapheme/base 
   
  utils/prepare_lang.sh $data/dict_grapheme/base  \
    "<UNK>" \
    $data/local_grapheme/tmp/base \
    $data/lang_grapheme/base 
  fi
  
  if [ $language == 'eng' ]; then
    #ToDo
    echo ToDo
  fi 

  if [ $language == 'es' ]; then
    #ToDo
    echo ToDo
  fi
fi

if [ $stage -le 3 ]; then
  echo ============================================================================
  echo "           	Aligning data and training the acoustic model                 "
  echo ============================================================================
  subset_size=10000
  # DemoData: To run this script with the demo data we need to change the subset size
  train_size=$(wc -l $data/combined/train/text | cut -d" " -f1)
  if [ $train_size -le $subset_size ]; then
    subset_size=$train_size
  fi

  echo "$0: Creating subset for monophone training"
  utils/subset_data_dir.sh $data/combined/train \
    $subset_size \
    $data/combined/train/train.${subset_size}K 

  echo "$0: Training mono system"
  steps/train_mono.sh --nj $num_jobs --cmd "$train_cmd" \
    $data/combined/train/train.${subset_size}K \
    $data/lang_grapheme/base \
    $exp/mono 
  
  echo "$0: Aligning data using monophone system" 
  steps/align_si.sh --nj $num_jobs \
    --cmd "$train_cmd" \
    $data/combined/train \
    $data/lang_grapheme/base \
    $exp/mono \
    $exp/mono_ali 
    
  echo "$0: Training triphone system with delta features"
  steps/train_deltas.sh --cmd "$train_cmd" \
    2500 30000 \
    $data/combined/train \
    $data/lang_grapheme/base \
    $exp/mono_ali \
    $exp/tri1 

  echo "$0: Aligning with tri1 model"
  steps/align_si.sh --nj $num_jobs \
    --cmd "$train_cmd" \
    $data/combined/train \
    $data/lang_grapheme/base \
    $exp/tri1 \
    $exp/tri1_ali
  
  echo "$0: Training with lda_mllt "
  steps/train_lda_mllt.sh --cmd "$train_cmd" \
    4000 50000 \
    $data/combined/train \
    $data/lang_grapheme/base \
    $exp/tri1_ali \
    $exp/tri2b 

  echo "$0: Aligning with lda_mllt model"
  steps/align_si.sh --nj $num_jobs \
    --cmd "$train_cmd" \
    $data/combined/train \
    $data/lang_grapheme/base \
    $exp/tri2b \
    $exp/tri2b_ali 

  echo "$0: Training tri3b LDA+MLLT+SAT system"
  steps/train_sat_basis.sh --cmd "$train_cmd" \
    5000 100000 \
    $data/combined/train \
    $data/lang_grapheme/base \
    $exp/tri2b_ali \
    $exp/tri3b 
fi

if [ $stage -le 4 ]; then
  echo ============================================================================
  echo "          TDNN training                                       "
  echo ============================================================================
  # ./run/02_run_tdnn.sh --stage 13 \
  #   --train-stage 19 \
  #   --langdir $data/lang_grapheme/base \
  #   --data $data/combined \
  #   --exp $exp \
  #   $data/combined/train \
  #   $data \
  #   >> $log/am_tdnn.log 2>&1

  ts=978
  run_again="true"
  while [ $run_again == "true" ]; do
    ./run/02_run_tdnn.sh --stage 13 \
      --train-stage $ts \
      --langdir $data/lang_grapheme/base \
      --data $data/combined \
      --exp $exp \
      $data/combined/train \
      $data \
      >> $log/am_tdnn.log 2>&1

    status=$(grep Iter: $log/am_tdnn.log | tail -n 1 | sed -E "s/.*Iter: //" | sed -e "s/Jobs:.*//")
    num=$(echo $status | sed -e "s/\/.*//")
    denom=$(echo $status | sed -e "s/.*\///")
    echo "Status: ${status}, num: ${num}, denom: ${denom}"
    
    if [ -n "$num" ] && [ $num == $denom ] ; then
      echo "We are done"
      run_again="false"
    else
      ts=$num
    fi
  done

fi