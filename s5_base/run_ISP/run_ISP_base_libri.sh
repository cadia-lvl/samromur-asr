#!/usr/bin/env bash
# Author David Erik Mollberg 2021


export LC_ALL=C

num_jobs=50
num_decode_jobs=30
code="libri"


libri_data=/work/derik/librispeech/LibriSpeech
text_corpus=/work/derik/librispeech/librispeech-lm-norm.txt

decode_lm=/home/derik/work/samromur-asr/s5_base/data_ISP/libri/lang_nosp_test_tgsmall
rescore_lm=/home/derik/work/samromur-asr/s5_base/data_ISP/libri/lang_nosp_test_tglarge

data=data_ISP
exp=exp_ISP
stage=1000
mfcc_dir=$exp/$code/mfcc

. utils/parse_options.sh || exit 1;
. path.sh
. cmd.sh 

#./setup.sh
#ln -s ../../kaldi/egs/librispeech/s5

if [ $stage -le 0 ]; then
  echo ============================================================================
  echo "                		Data Prep			                "
  echo ============================================================================
  for part in dev-clean test-clean dev-other test-other train-clean-100 train-clean-360 train-other-500; do
    s5/local/data_prep.sh $libri_data/$part $data/$code/$(echo $part | sed s/-/_/g)
  done

  echo ============================================================================
  echo "                		Prepare dict			                "
  echo ============================================================================
  lm_url=www.openslr.org/resources/11
  s5/local/download_lm.sh $lm_url \
                          $data/$code/local/lm

  s5/local/prepare_dict.sh --stage 3 \
                          --nj 30 \
                          --cmd "$train_cmd" \
                          $data/$code/local/lm \
                          $data/$code/local/lm \
                          $data/$code/local/dict_nosp

  utils/prepare_lang.sh $data/$code/local/dict_nosp \
                        "<UNK>" \
                        $data/$code/local/lang_tmp_nosp \
                        $data/$code/lang_nosp

  # This step prepares the language model that we downloaded with "download_lm.sh"
  s5/local/format_lms.sh --src-dir \
                        $data/$code/lang_nosp \
                        $data/$code/local/lm

  # Create ConstArpaLm format language model for full 3-gram and 4-gram LMs
    utils/build_const_arpa_lm.sh $data/$code/local/lm/lm_tglarge.arpa.gz \
                                $data/$code/lang \
                                $data/$code/lang_nosp_test_tglarge

    utils/build_const_arpa_lm.sh $data/$code/local/lm/lm_fglarge.arpa.gz \w
                                $data/$code/lang \
                                $data/$code/lang_nosp_test_fglarge


  # we have already extracted the features when we did the subwords step
  for x in train_clean_100 train_clean_360 train_other_500; do
    for file in cmvn.scp feats.scp utt2num_frames utt2dur; do
      cp ../s5_subwords/$data/$code/$x/$file $data/$code/$x/$file  
    done
  done


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
  utils/subset_data_dir.sh $data/$code/train_clean_100 $clips $data/libri_train_${x}h
  a=$(cut -d" " -f2  $data/libri_train_${x}h/utt2dur | awk '{s+=$1} END {print s/3600}')
  echo "${x}h:${a}h:${clips}" >> log

  x=20
  clips=5680
  utils/subset_data_dir.sh $data/$code/train_clean_100 $clips $data/libri_train_${x}h
  a=$(cut -d" " -f2  $data/libri_train_${x}h/utt2dur | awk '{s+=$1} END {print s/3600}')
  echo "${x}h:${a}h:${clips}" >> log

  x=40
  clips=11380
  utils/subset_data_dir.sh $data/$code/train_clean_100 $clips $data/libri_train_${x}h
  a=$(cut -d" " -f2  $data/libri_train_${x}h/utt2dur | awk '{s+=$1} END {print s/3600}')
  echo "${x}h:${a}h:${clips}" >> log

  x=80
  clips=22690
  utils/subset_data_dir.sh $data/$code/train_clean_100 $clips $data/libri_train_${x}h
  a=$(cut -d" " -f2  $data/libri_train_${x}h/utt2dur | awk '{s+=$1} END {print s/3600}')
  echo "${x}h:${a}h:${clips}" >> log

  # We now need to take from train_clean_360 as well. The total number of clips in train_clean_100
  # are 28539
  x=160
  clips_in_clean_100=28539
  clips=$(( 45525 - $clips_in_clean_100))
  echo $clips
  utils/subset_data_dir.sh $data/$code/train_clean_360 $clips $data/tmp
  utils/combine_data.sh $data/libri_train_${x}h $data/tmp $data/$code/train_clean_100
  rm -r $data/tmp
  a=$(cut -d" " -f2  $data/libri_train_${x}h/utt2dur | awk '{s+=$1} END {print s/3600}')
  echo "${x}h:${a}h:${clips}" >> log

  x=320
  clips_in_clean_100=28539
  clips=$(( 91300 - $clips_in_clean_100))
  echo $clips
  utils/subset_data_dir.sh $data/$code/train_clean_360 $clips $data/tmp
  utils/combine_data.sh $data/libri_train_${x}h $data/tmp $data/$code/train_clean_100
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
  utils/subset_data_dir.sh $data/$code/train_other_500 $clips $data/tmp
  utils/combine_data.sh $data/libri_train_${x}h $data/tmp $data/$code/train_clean_100 $data/$code/train_clean_360
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

  for x in 10h 20h; do
    (
    steps/train_mono.sh --nj $num_jobs --cmd "$train_cmd" \
                    $data/${code}_train_${x} \
                    $data/${code}/lang \
                    $exp/$code/${x}/mono 
    ) >> logs/${code}/${x}.log 2>&1 
  done

  for x in 40h 80h 160h 320h 640h; do
        (
        steps/train_mono.sh --nj $num_jobs --cmd "$train_cmd" \
                        $data/${code}_train_${x}/train.10K \
                        $data/${code}/lang \
                        $exp/$code/${x}/mono \
                         
        ) >> logs/${code}/${x}.log 2>&1 
  done

  echo ============================================================================
  echo "          Train tri1 delta+deltadelta system                               "
  echo ============================================================================
  echo "$0: Aligning $data using monophone system" 
  for x in 10h 20h 40h 80h 160h 320h 640h; do
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

    ) >> logs/${code}/${x}.log 2>&1
  done
  wait
    
  echo ============================================================================
  echo "     Train tri2 aligning $data and retraining and realigning with lda_mllt   "
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
      echo "$0: Aligning $data and retraining and realigning with sat_basis"
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
  echo "          Creating Lanuage models                                  "
  echo ============================================================================

  echo "Preparing an ${lm_order}g LM"
  $train_cmd --mem 50G "$code/make_LM_${lm_order}g_pruned.log" \
              local/lm/make_LM.sh \
              --order 3 \
              --pruning "0 2 10 20" \
              --carpa false \
              $text_corpus \
              $data/$code/lm \
              $data/$code/local/dict/lexicon.txt \
              data/lm_eng \
              "_pruned" \
              || error 1 "Failed creating an pruned ${lm_order}g LM";

  $train_cmd --mem 90G "logs/$code/make_LM_${lm_order}g_rescoring.log" \
              local/lm/make_LM.sh \
                --order 4  \
                --carpa true \
                $text_corpus \
                $data/$code/lang \
                $data/$code/local/dict/lexicon.txt \
                $data/lm_eng \
                "_rescore" \
                || error 1 "Failed creating an rescore ${lm_order}g LM";

  echo "Done creating an ${lm_order}g. The log is available logs/make_LM_${lm_order}g.log"

# 
# -----------------------------Let train the time delay neural network!-----------------------------
fi

if [ $stage -le 1 ]; then
for x in 10h 20h 40h 80h 160h 320h 640h; do
    time run_ISP/run_tdnn_ISP.sh --stage 13 \
                            --train_stage 818 \
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

fi

if [ $stage -le 2 ]; then

  for x in 640h; do
      time run_ISP/tdnn_decode.sh --stage 0 \
                                  --affix $x \
                                  --decoding-lang $decode_lm \
                                  --rescoring-lang $rescore_lm \
                                  --langdir $data/$code/lang \
                                  --exp $exp/$code/$x \
                                  $data/${code}_train_${x} \
                                  $data/$code \
                                  >> logs/$code/${x}_tdnn.log 2>&1
  done

fi