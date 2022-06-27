#!/usr/bin/env bash
# Copyright   2020 Reykjavik University (Authors: Judy Fong - judyfong@ru.is, Inga Run Helgadottir - ingarun@ru.is, Michal Borsky - michalb@ru.is)
# Apache 2.0
#
# See ../README.txt for more info on data required.
#SBATCH --output=logs/samrun%J.out
#SBATCH --nodelist=terra

# To be run from the s5_children directory

mfccdir=mfcc
nj_train=20
nj_decode=32
stage=0

. ./cmd.sh
. ./path.sh
# setup the steps and utils directories
. ./setup.sh
. ./local/utils.sh
. utils/parse_options.sh

set -eo pipefail

# NOTE! In the future the ASR data, LM training text and pronunciation dictionary
# will be downloaded from online first, e.g. Clarin
samromur_root=/data/asr/samromur/samromur_children_ldc
samromur_teen=/data/asr/samromur/samromur_teen
lm_train=/models/samromur/rmh_2020-11-23_uniq.txt
prondict_orig=/models/samromur/prondict_rmh_2020-12-02.txt
g2p_model=../preprocessing/g2p/ipd_clean_slt2018.mdl

# Created in this script
prondict=data/prondict_w_samromur.txt
localdict=data/local/dict

[ ! -d "$samromur_root" ] && echo "$0: expected $samromur_root to exist" && exit 1;
[ ! -d "$samromur_teen" ] && echo "$0: expected $samromur_teen to exist" && exit 1;
for f in "$lm_train" "$prondict_orig" "$g2p_model"; do \
  [ ! -f $f ] && echo "$0: expected $f to exist" && exit 1;
done

if [ $stage -le 0 ]; then
  echo "Create ./data directories"
  echo 'Adult speech'
  python3 local/samromur_prep_data.py "$samromur_root"/audio "$samromur_root"/metadata.tsv data
  
  echo "Teenage data"
  # Because of speaker ID overlap between adults and teenagers I add the letter t to the teen spkIDs
  sed -r 's/(\.wav[^0-9][0-9]+)\b/\1t/g' "$samromur_teen"/metadata.tsv > data/metadata_teen.tsv
  # I've removed out the generation of spk2gender for now, since there are also gender N and o
  # Also, I don't feel like gender will matter for kids
  python3 local/samromur_prep_data.py "$samromur_teen"/audio data/metadata_teen.tsv data/teen
  
fi

if [ $stage -le 1 ]; then
  echo "Make MFCC features"
  for name in train eval dev; do
    steps/make_mfcc.sh \
    --mfcc-config conf/mfcc.conf \
    --nj $nj_train --cmd "$train_cmd" \
    data/$name exp/make_mfcc $mfccdir \
    || error 1 "Failed creating MFCC features";
  done
fi

if [ $stage -le 2 ]; then
  echo "Comute CMVN"
  for name in train eval dev; do
    steps/compute_cmvn_stats.sh \
    data/$name exp/make_mfcc $mfccdir
    
    utils/validate_data_dir.sh data/"$name" || utils/fix_data_dir.sh data/"$name" || exit 1;
  done
fi

if [ $stage -le 3 ]; then
  echo "Identify OOV words"
  cut -d' ' -f2- data/train/text | tr ' ' '\n' | sort -u | grep -Ev '^$' \
  > data/train/wordlist.txt || exit 1;
  
  comm -23 data/train/wordlist.txt <(cut -f1 $prondict_orig | sort -u) \
  > data/train/oov_wordlist.txt || exit 1;
  
  echo "Use a grapheme-to-phoneme model to generate the pronunciation of OOV words in the training set"
  g2p.py --apply data/train/oov_wordlist.txt --model $g2p_model \
  --encoding="UTF-8" > data/train/oov_with_pron.txt || exit 1;
  
  echo "Add the OOV words to the prondict"
  cat $prondict_orig data/train/oov_with_pron.txt | sort -k1,1 | uniq > "$prondict" || exit 1;
  
  echo "Calculate the OOV rate in the dev and test set after"
  echo "incorporating the training text vocabulary into the lexicon"
  for n in eval dev; do
    nb_tokens=$(cut -d' ' -f2- data/$n/text | wc -w)
    cut -d' ' -f2- data/$n/text | tr ' ' '\n' | sort |uniq -c > data/$n/words.cnt || exit 1;
    
    comm -23 <(awk '$2 ~ /[[:print:]]/ { print $2 }' data/$n/words.cnt | sort) \
    <(cut -f1 $prondict | sort -u) > data/$n/vocab_text_only.tmp
    nb_oov=$(join -1 1 -2 1 data/$n/vocab_text_only.tmp <(awk '$2 ~ /[[:print:]]/ { print $2" "$1 }' \
    data/$n/words.cnt | sort -k1,1) | sort | awk '{total = total + $2}END{print total}')
    oov=$(echo "scale=3;$nb_oov/$nb_tokens*100" | bc)
    echo "The out of vocabulary rate for $n is: $oov" || exit 1;
  done > oov_rate
fi

if [ $stage -le 4 ]; then
  if [ ! -d data/lang ]; then
    echo "Create the lexicon"
    [ -d $localdict ] && rm -r $localdict
    mkdir -p $localdict data/lang/log
    $train_cmd data/lang/log/prep_lang.log \
    local/prep_lang.sh \
    $prondict $localdict data/lang
  fi
fi

if [ $stage -le 5 ]; then
  echo "Preparing a pruned trigram language model"
  mkdir -p data/log
  $train_cmd --mem 24G data/log/make_LM_3g.log \
  local/make_LM.sh \
  --order 3 --carpa false \
  --min1cnt 20 --min2cnt 10 --min3cnt 2 \
  $lm_train data/lang \
  $localdict/lexicon.txt data \
  || error 1 "Failed creating a pruned trigram language model";
  
  echo "Preparing an unpruned 4g LM"
  $train_cmd --mem 32G data/log/make_LM_4g.log \
  local/make_LM.sh \
  --order 4 --carpa true \
  --min1cnt 0 --min2cnt 0 --min3cnt 0 \
  $lm_train data/lang \
  $localdict/lexicon.txt data \
  || error 1 "Failed creating an unpruned 4-gram language model";
fi

# Subsample train for faster start
if [ $stage -le 6 ]; then
  echo "Make subsets of the training data to use for the first mono and triphone trainings"
  utils/subset_data_dir.sh data/train 5000 data/train_5k
  utils/subset_data_dir.sh data/train 10000 data/train_10k
fi


# train a monophone system
if [ $stage -le 7 ]; then
  
  echo "Train monophone system"
  steps/train_mono.sh \
  --nj $nj_train \
  --cmd "$train_cmd --mem 4G" \
  --boost-silence 1.25 \
  data/train_5k data/lang exp/mono
  
  echo "Mono alignment. Align train_10k to mono"
  steps/align_si.sh \
  --nj $nj_train --cmd "$train_cmd" \
  data/train_10k data/lang \
  exp/mono exp/mono_ali_10k
  
  echo "First triphone on train_10k, delta + delta-delta features"
  steps/train_deltas.sh \
  --cmd "$train_cmd --mem 4G" \
  2000 10000 \
  data/train_10k data/lang \
  exp/mono_ali_10k exp/tri1
fi

# Train LDA + MLLT
if [ $stage -le 8 ]; then
  echo "Aligning the train_10 set to tri1"
  steps/align_si.sh \
  --nj $nj_train \
  --cmd "$train_cmd" \
  data/train_10k data/lang \
  exp/tri1 exp/tri1_ali_10k
  
  echo "Train LDA + MLLT"
  steps/train_lda_mllt.sh \
  --cmd "$train_cmd --mem 4G"  \
  4000 40000 data/train_10k \
  data/lang exp/tri1_ali_10k exp/tri2
fi

# Train LDA + MLLT + SAT
if [ $stage -le 9 ]; then
  echo "Aligning the full training set to tri2"
  steps/align_fmllr.sh \
  --nj $nj_train \
  --cmd "$train_cmd" \
  data/train data/lang \
  exp/tri2 exp/tri2_ali
  
  echo "Train LDA + MLLT + SAT"
  steps/train_sat.sh --cmd "$train_cmd --mem 4G"  4000 40000 data/train \
  data/lang exp/tri2_ali exp/tri3
fi

# Tri3 decoding
if [ $stage -le 10 ]; then
  echo "Triphone tri3 decoding"
  $train_cmd --mem 4G exp/tri3/log/mkgraph.log \
  utils/mkgraph.sh \
  data/lang_3g exp/tri3 \
  exp/tri3/graph
  
  for dir in dev eval; do
    (
      steps/decode_fmllr.sh \
      --config conf/decode.config \
      --nj "$nj_decode"  \
      --cmd "$decode_cmd" \
      exp/tri3/graph data/$dir \
      exp/tri3/decode_$dir;
      
      steps/lmrescore_const_arpa.sh \
      --cmd "$decode_cmd" \
      data/lang_{3g,4g} data/$dir \
      exp/tri3/decode_$dir \
      exp/tri3/decode_${dir}_rescored
    ) &
  done
  wait
  
  # WER info:
  for x in exp/*/decode_{eval,dev}_rescored; do
    [ -d "$x" ] && grep WER "$x"/wer_* | utils/best_wer.sh;
  done > RESULTS
fi

if [ $stage -le 11 ]; then
  
  echo "Create a joint training set with adult and teenage data"
  utils/data/combine_data.sh data/train_w_teen data/train data/teen/train
fi

if [ $stage -le 1 ]; then
  echo "Make MFCC features for adult + teen training set"
  steps/make_mfcc.sh \
  --mfcc-config conf/mfcc.conf \
  --nj $nj_train --cmd "$train_cmd" \
  data/train_w_teen exp/make_mfcc $mfccdir \
  || error 1 "Failed creating MFCC features";
  
  echo "Comute CMVN"
  steps/compute_cmvn_stats.sh \
  data/train_w_teen exp/make_mfcc $mfccdir
  
  utils/validate_data_dir.sh data/train_w_teen || utils/fix_data_dir.sh data/train_w_teen || exit 1;
  
  echo "Make MFCC features for the teen test data"
  for name in eval dev; do
    steps/make_mfcc.sh \
    --mfcc-config conf/mfcc.conf \
    --nj $nj_train --cmd "$train_cmd" \
    data/teen/$name exp/make_mfcc $mfccdir \
    || error 1 "Failed creating MFCC features";
  done
  
  echo "Comute CMVN"
  for name in eval dev; do
    steps/compute_cmvn_stats.sh \
    data/teen/$name exp/make_mfcc $mfccdir
    
    utils/validate_data_dir.sh data/teen/"$name" || utils/fix_data_dir.sh data/teen/"$name" || exit 1;
  done
  
fi

if [ $stage -le 12 ]; then
  echo "Aligning the combined training set to tri3"
  steps/align_fmllr.sh \
  --nj $nj_train \
  --cmd "$decode_cmd" \
  data/train_w_teen data/lang \
  exp/tri3 exp/tri3_ali
  
  echo "Train LDA + MLLT + SAT on the combined training set"
  steps/train_sat.sh \
  --cmd "$train_cmd --mem 4G"  \
  4000 40000 data/train_w_teen \
  data/lang exp/tri3_ali exp/tri4
fi

if [ $stage -le 13 ]; then
  echo "Triphone tri4 decoding. Adult + teen data."
  $train_cmd --mem 4G exp/tri4/log/mkgraph.log \
  utils/mkgraph.sh \
  data/lang_3g exp/tri4 \
  exp/tri4/graph
  
  echo "Decode both for adult and teen test sets"
  for dir in dev eval; do
    (
      steps/decode_fmllr.sh \
      --config conf/decode.config \
      --nj "$nj_decode"  \
      --cmd "$decode_cmd" \
      exp/tri4/graph data/$dir \
      exp/tri4/decode_$dir;
      
      steps/lmrescore_const_arpa.sh \
      --cmd "$decode_cmd" \
      data/lang_{3g,4g} data/$dir \
      exp/tri4/decode_$dir \
      exp/tri4/decode_${dir}_rescored
    ) &
    (
      steps/decode_fmllr.sh \
      --config conf/decode.config \
      --nj "$nj_decode"  \
      --cmd "$decode_cmd" \
      exp/tri4/graph data/teen/$dir \
      exp/tri4/decode_teen_$dir;
      
      steps/lmrescore_const_arpa.sh \
      --cmd "$decode_cmd" \
      data/lang_{3g,4g} data/teen/$dir \
      exp/tri4/decode_teen_$dir \
      exp/tri4/decode_teen_${dir}_rescored
    ) &
  done
  wait
  
fi

if [ $stage -le 14 ]; then
  
  affix=_7n
  speed_perturb=true
  nohup local/chain/run_tdnn.sh \
  --stage 0 --affix $affix \
  --speed-perturb $speed_perturb \
  --generate-plots true \
  data/train_w_teen data >>logs/tdnn$affix.log 2>&1 &
  # I want to --generate-plots true --zerogram-decoding true \
  
  # WER info:
  for x in exp/chain/tdnn"$affix"/decode*; do [ -d "$x" ] && grep WER "$x"/wer_* | utils/best_wer.sh; done >> RESULTS
  
fi

exit 0
