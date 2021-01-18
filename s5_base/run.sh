#!/usr/bin/env bash
# Copyright   2020 Reykjavik University (Author: Judy Fong - judyfong@ru.is)
# Apache 2.0
#
# See ../README.txt for more info on data required.
#SBATCH --output=logs/samrun%J.out
#SBATCH --nodelist=terra

# To be run from the s5_base directory

mfccdir=mfcc
num_jobs=20
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
samromur_root=/data/asr/samromur/samromur_ldc #samromur
lm_train=/models/samromur/rmh_2020-11-23_uniq.txt
prondict_orig=/models/samromur/prondict_rmh_2020-12-02.txt
g2p_model=../preprocessing/g2p/ipd_clean_slt2018.mdl

# Created in this script
prondict=data/prondict_w_samromur.txt
localdict=data/local/dict

[ ! -d "$samromur_root" ] && echo "$0: expected $samromur_root to exist" && exit 1;
for f in "$lm_train" "$prondict_orig" "$g2p_model"; do \
    [ ! -f $f ] && echo "$0: expected $f to exist" && exit 1;
done

if [ $stage -le 0 ]; then
    echo "Create training data"
    local/samromur_data_prep.sh $samromur_root train data
    local/samromur_data_prep.sh $samromur_root dev data
    local/samromur_data_prep.sh $samromur_root eval data
    
    utils/fix_data_dir.sh data/train
    utils/fix_data_dir.sh data/dev
    utils/fix_data_dir.sh data/eval
fi

# Prepare features
if [ $stage -le 1 ]; then
    echo "Make mfccs"
    # Make MFCCs for each dataset
    for name in train eval dev; do
        steps/make_mfcc.sh \
        --mfcc-config conf/mfcc.conf \
        --nj ${num_jobs} \
        --cmd "$train_cmd --mem 4G" \
        data/${name} exp/make_mfcc $mfccdir \
        || error 1 "Failed creating MFCC features";
    done
fi

if [ $stage -le 2 ]; then
    echo "Comute cmvn"
    for name in train eval dev; do
        steps/compute_cmvn_stats.sh \
        data/${name} exp/make_mfcc $mfccdir;
        
        utils/validate_data_dir.sh data/"$name" \
        || utils/fix_data_dir.sh data/"$name" || exit 1;
    done
fi

if [ $stage -le 3 ]; then
    echo "Identify OOV words"
    cut -d' ' -f2- data/train/text \
    | tr ' ' '\n' | sort -u | grep -Ev '^$' \
    > data/train/wordlist.txt || exit 1;
    
    comm -23 data/train/wordlist.txt \
    <(cut -f1 $prondict_orig | sort -u) \
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
        cut -d' ' -f2- data/$n/text \
        | tr ' ' '\n' | sort |uniq -c \
        > data/$n/words.cnt || exit 1;
        
        comm -23 <(awk '$2 ~ /[[:print:]]/ { print $2 }' data/$n/words.cnt | sort) \
        <(cut -f1 $prondict | sort -u) > data/$n/vocab_text_only.tmp
        nb_oov=$(join -1 1 -2 1 data/$n/vocab_text_only.tmp <(awk '$2 ~ /[[:print:]]/ { print $2" "$1 }' data/$n/words.cnt | sort -k1,1) \
        | sort | awk '{total = total + $2}END{print total}')
        oov=$(echo "scale=3;$nb_oov/$nb_tokens*100" | bc)
        echo "The out of vocabulary rate for $n is: $oov" >> oov_rate || exit 1;
    done
fi

if [ $stage -le 4 ]; then
    if [ ! -d data/lang ]; then
        echo "Create the lexicon"
        [ -d $localdict ] && rm -r $localdict
        mkdir -p $localdict data/lang/log
        $train_cmd --mem 4G data/lang/log/prep_lang.log \
        local/prep_lang.sh \
        $prondict        \
        $localdict   \
        data/lang
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
    || error 1 "Failed creating a pruned trigram language model"
    
    echo "Preparing an unpruned 4g LM"
    $train_cmd --mem 32G data/log/make_LM_4g.log \
    local/make_LM.sh \
    --order 4 --carpa true \
    --min1cnt 1 --min2cnt 0 --min3cnt 0 \
    $lm_train data/lang \
    $localdict/lexicon.txt data \
    || error 1 "Failed creating an unpruned 4-gram language model"
    
fi

# train a monophone system
if [ $stage -le 6 ]; then
    echo "Make subsets of the training data to use for the first mono and triphone trainings"
    
    utils/subset_data_dir.sh data/train 40000 data/train_40k
    utils/subset_data_dir.sh --shortest data/train_40k 5000 data/train_5kshort
    utils/subset_data_dir.sh data/train 10000 data/train_20k
fi

if [ $stage -le 7 ]; then
    
    echo "Train monophone system"
    steps/train_mono.sh \
    --nj $num_jobs \
    --cmd "$train_cmd --mem 4G" \
    --boost-silence 1.25 \
    data/train_5kshort \
    data/lang          \
    exp/mono
    
    echo "mono alignment. Align train_20k to mono"
    steps/align_si.sh \
    --nj $num_jobs --cmd "$train_cmd" \
    data/train_20k data/lang \
    exp/mono exp/mono_ali
    
    echo "First triphone training, delta + delta-delta features"
    steps/train_deltas.sh  \
    --cmd "$train_cmd --mem 4G" \
    2000 10000         \
    data/train_20k data/lang \
    exp/mono_ali exp/tri1
    
fi

if [ $stage -le 8 ]; then
    echo "First triphone decoding"
    $train_cmd --mem 4G exp/tri1/log/mkgraph.log \
    utils/mkgraph.sh data/lang_3g exp/tri1 exp/tri1/graph
    
    for dir in dev eval; do
        (
            steps/decode.sh \
            --config conf/decode.config \
            --nj "$nj_decode" --cmd "$decode_cmd" \
            exp/tri1/graph data/$dir \
            exp/tri1/decode_$dir;
            
            steps/lmrescore_const_arpa.sh \
            --cmd "$decode_cmd" \
            data/lang_{3g,4g} data/$dir \
            exp/tri1/decode_$dir \
            exp/tri1/decode_${dir}_rescored
        ) &
    done
    wait
    
fi

if [ $stage -le 9 ]; then
    echo "Aligning train_40k to tri1"
    steps/align_si.sh \
    --nj $num_jobs --cmd "$train_cmd" \
    data/train_40k data/lang \
    exp/tri1 exp/tri1_ali
    
    echo "Training LDA + MLLT system tri2"
    steps/train_lda_mllt.sh \
    --cmd "$train_cmd --mem 4G" \
    --splice-opts "--left-context=3 --right-context=3" \
    2500 15000 \
    data/train_40k data/lang \
    exp/tri1_ali exp/tri2
    
fi

if [ $stage -le 10 ]; then
    echo "Second triphone decoding"
    $train_cmd --mem 4G exp/tri2/log/mkgraph.log \
    utils/mkgraph.sh data/lang_3g exp/tri2 exp/tri2/graph
    
    for dir in dev eval; do
        (
            steps/decode.sh \
            --config conf/decode.config \
            --nj "$nj_decode" --cmd "$decode_cmd" \
            exp/tri2/graph data/$dir \
            exp/tri2/decode_$dir;
            
            steps/lmrescore_const_arpa.sh \
            --cmd "$decode_cmd" \
            data/lang_{3g,4g} data/$dir \
            exp/tri2/decode_$dir \
            exp/tri2/decode_${dir}_rescored
        ) &
    done
    wait
    
fi

if [ $stage -le 11 ]; then
    echo "Aligning the full training set to tri2"
    steps/align_si.sh \
    --nj $num_jobs --cmd "$train_cmd" \
    data/train data/lang \
    exp/tri2 exp/tri2_ali
    
    echo "Train LDA + MLLT + SAT"
    steps/train_sat.sh    \
    --cmd "$train_cmd --mem 4G" \
    4000 40000    \
    data/train data/lang     \
    exp/tri2_ali exp/tri3
    
fi

if [ $stage -le 12 ]; then
    echo "Third triphone decoding"
    $train_cmd --mem 4G exp/tri3/log/mkgraph.log \
    utils/mkgraph.sh data/lang_3g exp/tri3 exp/tri3/graph
    
    for dir in dev eval; do
        (
            steps/decode_fmllr.sh \
            --config conf/decode.config \
            --nj "$nj_decode" --cmd "$decode_cmd" \
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
fi

# WER info:
for x in exp/*/decode_eval_rescored; do [ -d "$x" ] && grep WER "$x"/wer_* | utils/best_wer.sh; done >> RESULTS

exit 0