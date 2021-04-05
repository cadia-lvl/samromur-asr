#!/usr/bin/env bash
# Copyright   2020 Reykjavik University (Authors: Judy Fong - judyfong@ru.is, Inga Run Helgadottir - ingarun@ru.is, Michal Borsky - michalb@ru.is)
# Apache 2.0
#
# See ../README.txt for more info on data required.
#SBATCH --output=logs/samrun%J.out
#SBATCH --nodelist=terra

# To be run from the s5_base directory

mfccdir=mfcc
num_jobs=30
num_decode_jobs=30
ts="hello"
set=10000
stage=100
create_lm=false
. ./cmd.sh
. ./path.sh
. utils/parse_options.sh

data=data_ISP
exp=exp_ISP
code=isl

decode_lm=$data/isl_lm/lang_3g
rescore_lm=$data/isl_lm/lang_4g
g2p_model=../preprocessing/g2p/ipd_clean_slt2018.mdl
text_corpus=/work/derik/language_models/LM_corpus/rmh_2020-11-23_shuffle+malromur.txt


prondict=$data/isl_local/new_lexicon.txt

if [ $stage -le 0 ]; then
  # we have already extracted the features when we did the subwords step
  for x in 10h 20h 40h 80h 160h 320h 640h; do
      mkdir -p $data/${code}_train_${x}
      for file in cmvn.scp feats.scp reco2dur segments spk2utt utt2num_frames text utt2num_frames utt2dur utt2spk wav.scp; do
          cp ../s5_subwords/$data/${code}_train_${x}/$file $data/${code}_train_${x}/$file  
    done 
  done

  # lets remove the subword tokenization
  for x in 10h 20h 40h 80h 160h 320h 640h; do
      sed 's/@@ //g' $data/${code}_train_${x}/text > $data/${code}_train_${x}/text.norm
      mv $data/${code}_train_${x}/text.norm $data/${code}_train_${x}/text 
  done

  # We had already constructed the lexicon and language models
  cp -r /models/samromur/dict/ $data/isl_dict 


  # lest identify the OOV words" 
  cut -d' ' -f2- $data/isl_train_640h/text | tr ' ' '\n' | sort -u | grep -Ev '^$' > $data/isl_local/wordlist.txt 
      
  comm -23 $data/isl_local/wordlist.txt <(cut -f1 $data/isl_dict/lexicon.txt | sort -u) > $data/isl_local/oov_wordlist.txt 
            
  echo "Use a grapheme-to-phoneme model to generate the pronunciation of OOV words in the training set"
  g2p.py --apply $data/isl_local/oov_wordlist.txt --model $g2p_model --encoding="UTF-8" > $data/isl_local/oov_with_pron.txt 
      
  echo "Add the OOV words to the prondict"
  cat $data/isl_dict/lexicon.txt $data/isl_local/oov_with_pron.txt | sort -k1,1 | uniq > $prondict
      

  echo "Calculate the OOV rate in the dev and test set after"
  echo "incorporating the training text vocabulary into the lexicon"
  for n in althingi_dev_hires althingi_test_hires sm_dev_hires sm_test_hires; do
      nb_tokens=$(cut -d' ' -f2- $data/sm/$n/text | wc -w)
      cut -d' ' -f2- $data/sm/$n/text | tr ' ' '\n' | sort | uniq -c > $data/sm/$n/words.cnt 
      
      comm -23 <(awk '$2 ~ /[[:print:]]/ { print $2 }' $data/sm/$n/words.cnt | sort) \
                      <(cut -f1 $prondict | sort -u) > $data/sm/$n/vocab_text_only.tmp
      nb_oov=$(join -1 1 -2 1 $data/sm/$n/vocab_text_only.tmp <(awk '$2 ~ /[[:print:]]/ { print $2" "$1 }' \
            $data/sm/$n/words.cnt | sort -k1,1) | sort | awk '{total = total + $2}END{print total}')
      oov=$(echo "scale=3;$nb_oov/$nb_tokens*100" | bc)
      echo "The out of vocabulary rate for $n is: $oov" 
  done > oov_rate


  echo "Create the lexicon"
  local/prep_lang.sh $prondict \
                    $data/isl_dict \
                    $data/isl_lang &> log


  echo ============================================================================
  echo "          Train mono system                                               "
  echo ============================================================================
  # Lets now create a monophone system
  # We start by taking 10k utterances subset for faster training. 
  # We don't do that for the smallest coprora as it has less then 
  # 10k utternaces
  for x in 10h 20h 40h 80h 160h 320h 640h; do
    echo $x
    utils/validate_data_dir.sh $data/${code}_train_${x} || utils/fix_data_dir.sh $data/${code}_train_${x}
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
                  $exp/$code/10h/mono 

  for x in 20h 40h 80h 160h 320h 640h; do
        (
        echo $code $x
        steps/train_mono.sh --nj $num_jobs --cmd "$train_cmd" \
                        $data/${code}_train_${x}/train.10K \
                        $data/${code}_lang \
                        $exp/$code/${x}/mono \
                        >> logs/${code}/${x}.log 2>&1 
        ) 
  done
  wait

  echo ============================================================================
  echo "          Train tri1 delta+deltadelta system                               "
  echo ============================================================================
  echo "$0: Aligning data using monophone system" 
  for x in 160h 320h 640h; do
    (
    echo $code $x  
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
      echo $code $x
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
      echo $code $x
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
# skref 13 er tauganetið

if [ $stage -le 1 ]; then
  run_again="true"
  tdnn_stage=7
  while [ $run_again == "true" ]; do
    for x in $set; do
      echo $code, $x
      time run_ISP/run_tdnn_ISP.sh --stage $tdnn_stage \
                                  --train_stage $ts \
                                  --affix $x \
                                  --decoding-lang $decode_lm \
                                  --rescoring-lang $rescore_lm \
                                  --langdir $data/${code}_lang \
                                  --data $data/${code}_train_${x} --exp $exp/$code/$x \
                                  $data/${code}_train_${x} \
                                  $data/sm \
                                  >> logs/$code/${x}_tdnn.log 2>&1
                      
    done
    status=$(grep Iter: logs/$code/${x}_tdnn.log | tail -n 1 | sed -E "s/.*Iter: //" | sed -e "s/Jobs:.*//")
    num=$(echo $status | sed -e "s/\/.*//")
    denom=$(echo $status | sed -e "s/.*\///")
    echo "Status: ${status}, num: ${num}, denom: ${denom}, here"
    
    if [ -n "$num" ] && [ $num == $denom ] ; then
      echo "We are done"
      run_again="false"
    else
      echo "here"
      tdnn_stage=13
      ts=$num
    fi
  done
fi

if [ $stage -le 2 ] && $create_lm; then

  echo ============================================================================
  echo "                		Prepare LM           "
  echo ============================================================================
      # We create two language model  
      # One for decoding kenlm 6g, pruning: 0 2 5 10, bpe3000, arpa
      # Another for rescoring kenlm 10g, pruning: 0 2, bpe3000, carpa
     
  lm_order=3
  echo "Preparing an ${lm_order}g LM"
  $train_cmd --mem 80G "logs/$code/lm/make_LM_${lm_order}g_pruned.log" \
            ../s5_subwords/local/lm/make_LM.sh \
            --order $lm_order \
            --pruning "2 10 15" \
            --carpa false \
            $text_corpus \
            $data/${code}_lang \
            $data/${code}_dict/lexicon.txt \
            $data/lm_ice \
            "_pruned" \
            || error 1 "Failed creating an pruned ${lm_order}g LM";

  echo "Done creating an ${lm_order}g. The log is available logs/make_LM_${lm_order}g.log"

  # Creating an minimum pruned lm for rescoring
  lm_order=4
  echo "Preparing an ${lm_order}g LM"
  $train_cmd --mem 70G --config conf/slurm_torpaq.conf "logs/$code/lm/make_LM_${lm_order}gv2.log" \
            ../s5_subwords/local/lm/make_LM.sh \
            --order $lm_order \
            --pruning "0 2" \
            --carpa true \
            $text_corpus \
            $data/${code}_lang \
            $data/${code}_dict/lexicon.txt \
            $data/isl_lm/v2 \
            "carpa" \
            || error 1 "Failed creating an ${lm_order}g LM";

  echo "Done creating an ${lm_order}g. The log is available logs/make_LM_${lm_order}g.log"
    

fi

if [ $stage -le 3 ]; then

  for x in 640h; do
      echo decoding $code $x

      time run_ISP/tdnn_decode.sh --stage 0 \
                                  --affix $x \
                                  --decoding-lang $decode_lm \
                                  --rescoring-lang $rescore_lm \
                                  --langdir $data/${code}_lang \
                                  --exp $exp/$code/$x \
                                  $data/${code}_train_${x} \
                                  $data/sm \
                                  >> logs/$code/${x}_tdnn.log 2>&1
  done


fi

echo done
exit 1

# OOV calculations
for decode_set in sm_dev_hires sm_test_hires althingi_dev_hires althingi_test_hires; do
    ./run_ISP/oov.py data_ISP/sm/$decode_set/text data_ISP/isl_lang/words.txt data_ISP/sm/$decode_set/oov
done

# In the file:data_ISP/sm/sm_dev_hires/text
# there are 249 or a 0.00026035866759099223% oovs rate

# In the file:data_ISP/sm/sm_test_hires/text
# there are 284 or a 0.0002969552674531799% oovs rate

# In the file:data_ISP/sm/althingi_dev_hires/text
# there are 290 or a 0.0003032289702866978% oovs rate

# In the file:data_ISP/sm/althingi_test_hires/text
# there are 306 or a 0.0003199588445094121% oovs rate
