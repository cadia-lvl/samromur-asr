#--------------------------------------------------------------------#
# Copyright   2021 Reykjavik University (Authors: Carlos Daniel 
#Hernández Mena - carlosm@ru.is)

#Based on a previous recipe by: Judy Fong - judyfong@ru.is, 
#Inga Run Helgadottir - ingarun@ru.is and 
#Michal Borsky - michalb@ru.is

# Apache 2.0
#
# See ../README.txt for more info on data required.
#SBATCH --output=logs/samrun%J.out
#SBATCH --nodelist=terra
#--------------------------------------------------------------------#
# To be run from the s5_tdnn_lstm directory

echo "-----------------------------"
echo "Initialization ..."
echo "-----------------------------"

#--------------------------------------------------------------------#
#Setting up important paths and variables
#--------------------------------------------------------------------#
# NOTE! In the future the ASR data, LM training text and pronunciation 
#dictionary will be downloaded from online first, e.g. Clarin

samromur_root=/data/asr/samromur/samromur_v1/samromur_v1
lm_train=/models/samromur/rmh_2020-11-23_uniq.txt
#prondict_orig=/models/samromur/prondict_rmh_2020-12-02.txt
prondict_orig=local/etc/Pronounciation_Dictionary_April_2021.dic
g2p_model=../preprocessing/g2p/ipd_clean_slt2018.mdl

# Created in this script
prondict=data/prondict_w_samromur.txt
localdict=data/local/dict

#--------------------------------------------------------------------#
nj_train=30
nj_decode=32
stage=0
#--------------------------------------------------------------------#
#Setting up Kaldi paths and commands
. ./cmd.sh
. ./path.sh
# setup the steps and utils directories
. ./setup.sh
. ./local/utils.sh
. utils/parse_options.sh

#Exit immediately in case of error.
set -eo pipefail

#--------------------------------------------------------------------#
#Verifiying that some important files are in place.
#--------------------------------------------------------------------#

[ ! -d "$samromur_root" ] && echo "$0: expected $samromur_root to exist" && exit 1;
for f in "$lm_train" "$prondict_orig" "$g2p_model"; do \
    [ ! -f $f ] && echo "$0: expected $f to exist" && exit 1;
done

#--------------------------------------------------------------------#
#Data Preparation
#--------------------------------------------------------------------#

if [ $stage -le 0 ]; then
    echo "-----------------------------"
    echo "Create ./data directories"
    echo "-----------------------------"
    for name in train dev eval; do
        local/samromur_data_prep.sh $samromur_root $name data
        python3 local/fix_text.py data/$name
        utils/fix_data_dir.sh data/$name
    done
    echo "INFO (run.sh): Stage 0 Done!"
fi

#--------------------------------------------------------------------#
#MFCC Calculation
#--------------------------------------------------------------------#

# Prepare MFCC features
if [ $stage -le 1 ]; then
    echo "-----------------------------"
    echo "Make mfccs"
    echo "-----------------------------"
    for name in train eval dev; do
        steps/make_mfcc.sh \
        --mfcc-config conf/mfcc.conf \
        --nj $nj_train --cmd "$train_cmd" \
        data/$name exp/make_mfcc $mfccdir \
        || error 1 "Failed creating MFCC features";
    done
    echo "INFO (run.sh): Stage 1 Done!"
fi

#--------------------------------------------------------------------#
#Computing Cepstral Mean and Variance Normalization statistics (CMVN)
#--------------------------------------------------------------------#

if [ $stage -le 2 ]; then
    echo "-----------------------------"
    echo "Compute CMVN"
    echo "-----------------------------"
    for name in train eval dev; do
        steps/compute_cmvn_stats.sh \
        data/$name exp/make_mfcc $mfccdir
        
        utils/validate_data_dir.sh data/"$name" || utils/fix_data_dir.sh data/"$name" || exit 1;
    done
    echo "INFO (run.sh): Stage 2 Done!"
fi

#--------------------------------------------------------------------#
#Identify Out-of-Vocabulary (OOV) words
#--------------------------------------------------------------------#
#Sequitur-g2p is needed for this stage. Install here:
#https://github.com/sequitur-g2p/sequitur-g2p

if [ $stage -le 3 ]; then
    echo "-----------------------------"
    echo "Identify OOV words"
    echo "-----------------------------"
    cut -d' ' -f2- data/train/text | tr ' ' '\n' | sort -u | grep -Ev '^$' \
    > data/train/wordlist.txt || exit 1;
    
    comm -23 data/train/wordlist.txt <(cut -f1 $prondict_orig | sort -u) \
    > data/train/oov_wordlist.txt || exit 1;
    
    echo "-----------------------------"
    echo "Use a grapheme-to-phoneme model to generate the pronunciation of OOV words in the training set"
    echo "-----------------------------"
    g2p.py --apply data/train/oov_wordlist.txt --model $g2p_model \
    --encoding="UTF-8" > data/train/oov_with_pron.txt || exit 1;

    echo "-----------------------------"
    echo "Add the OOV words to the prondict"
    echo "-----------------------------"
    cat $prondict_orig data/train/oov_with_pron.txt | sort -k1,1 | uniq > "$prondict" || exit 1;

    echo "-----------------------------"
    echo "Calculate the OOV rate in the dev and test set after"
    echo "incorporating the training text vocabulary into the lexicon"
    echo "-----------------------------"
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
    echo "INFO (run.sh): Stage 3 Done!"
fi

#--------------------------------------------------------------------#
#Create the Lexicon
#--------------------------------------------------------------------#

if [ $stage -le 4 ]; then
    if [ ! -d data/lang ]; then
        echo "-----------------------------"
        echo "Create the lexicon"
        echo "-----------------------------"
        [ -d $localdict ] && rm -r $localdict
        mkdir -p $localdict data/lang/log
        $decode_cmd data/lang/log/prep_lang.log \
        local/prep_lang.sh \
        $prondict $localdict data/lang
    fi
    echo "INFO (run.sh): Stage 4 Done!"
fi

#--------------------------------------------------------------------#
#Create the language models
#--------------------------------------------------------------------#

if [ $stage -le 5 ]; then
    echo "-----------------------------"
    echo "Preparing a pruned trigram language model"
    echo "-----------------------------"
    mkdir -p data/log
    $train_cmd --mem 24G data/log/make_LM_3g.log \
    local/make_LM.sh \
    --order 3 --carpa false \
    --min1cnt 20 --min2cnt 10 --min3cnt 2 \
    $lm_train data/lang \
    $localdict/lexicon.txt data \
    || error 1 "Failed creating a pruned trigram language model";

    echo "-----------------------------"
    echo "Preparing an unpruned 4g LM"
    echo "-----------------------------"
    $train_cmd --mem 32G data/log/make_LM_4g.log \
    local/make_LM.sh \
    --order 4 --carpa true \
    --min1cnt 0 --min2cnt 0 --min3cnt 0 \
    $lm_train data/lang \
    $localdict/lexicon.txt data \
    || error 1 "Failed creating an unpruned 4-gram language model";

    echo "INFO (run.sh): Stage 5 Done!"
fi

#--------------------------------------------------------------------#
## Subsample train for faster start
#--------------------------------------------------------------------#

if [ $stage -le 6 ]; then
    echo "-----------------------------"
    echo "Make subsets of the training data to use for the first mono and triphone trainings"
    echo "-----------------------------"
    utils/subset_data_dir.sh data/train 5000 data/train_5k
    utils/subset_data_dir.sh data/train 10000 data/train_10k

    echo "INFO (run.sh): Stage 6 Done!"
fi

#--------------------------------------------------------------------#
#Train a monophone system
#--------------------------------------------------------------------#

if [ $stage -le 7 ]; then
    echo "-----------------------------"
    echo "Train monophone system"
    echo "-----------------------------"
    steps/train_mono.sh \
    --nj $nj_train \
    --cmd "$train_cmd --mem 4G" \
    --boost-silence 1.25 \
    data/train_5k data/lang exp/mono
    echo "-----------------------------"
    echo "Mono alignment. Align train_10k to mono"
    echo "-----------------------------"
    steps/align_si.sh \
    --nj $nj_train --cmd "$train_cmd --mem 4G" \
    data/train_10k data/lang \
    exp/mono exp/mono_ali_10k
    echo "-----------------------------"
    echo "First triphone on train_10k, delta + delta-delta features"
    echo "-----------------------------"
    steps/train_deltas.sh \
    --cmd "$train_cmd --mem 4G" \
    2000 10000 \
    data/train_10k data/lang \
    exp/mono_ali_10k exp/tri1

    echo "INFO (run.sh): Stage 7 Done!"
fi

#--------------------------------------------------------------------#
#Train LDA + MLLT
#--------------------------------------------------------------------#

if [ $stage -le 8 ]; then
    echo "-----------------------------"
    echo "Aligning the train_10 set to tri1"
    echo "-----------------------------"
    steps/align_si.sh \
    --nj $nj_train \
    --cmd "$train_cmd --mem 4G" \
    data/train_10k data/lang \
    exp/tri1 exp/tri1_ali_10k
    
    echo "-----------------------------"
    echo "Train LDA + MLLT"
    echo "-----------------------------"
    steps/train_lda_mllt.sh \
    --cmd "$train_cmd --mem 4G"  \
    4000 40000 data/train_10k \
    data/lang exp/tri1_ali_10k exp/tri2

    echo "INFO (run.sh): Stage 8 Done!"
fi

#--------------------------------------------------------------------#
#Train LDA + MLLT + SAT
#--------------------------------------------------------------------#

if [ $stage -le 9 ]; then
    echo "-----------------------------"
    echo "Aligning the full training set to tri2"
    echo "-----------------------------"
    steps/align_fmllr.sh \
    --nj $nj_train \
    --cmd "$train_cmd --mem 4G" \
    data/train data/lang \
    exp/tri2 exp/tri2_ali
    
    echo "-----------------------------"
    echo "Train LDA + MLLT + SAT"
    echo "-----------------------------"
    steps/train_sat.sh --cmd "$train_cmd --mem 4G"  4000 40000 data/train \
    data/lang exp/tri2_ali exp/tri3

    echo "INFO (run.sh): Stage 9 Done!"
fi

#--------------------------------------------------------------------#
#Tri3 decoding
#--------------------------------------------------------------------#

if [ $stage -le 10 ]; then
    echo "-----------------------------"
    echo "Triphone tri3 decoding"
    echo "-----------------------------"
    $mkgraph_cmd exp/tri3/log/mkgraph.log \
    utils/mkgraph.sh \
    data/lang_3g exp/tri3 \
    exp/tri3/graph
    echo "INFO (run.sh): mkpraph.h Done!"
    
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
    echo "INFO (run.sh): Stage 10 Done!"
fi

#--------------------------------------------------------------------#
#Report WER Results
#--------------------------------------------------------------------#

for x in exp/*/decode_{eval,dev}_rescored; do
    [ -d "$x" ] && grep WER "$x"/wer_* | utils/best_wer.sh;
done > RESULTS

##--------------------------------------------------------------------#
##TDNN-LSTM
##--------------------------------------------------------------------#

if [ $stage -le 11 ]; then
    local/chain/run_tdnn_lstm.sh --stage 0 --train-set train --gmm tri3 --nnet3-affix ""
    wait
    echo "INFO (run.sh): Stage 11 Done!"
fi

#--------------------------------------------------------------------#
#Report WER Results
#--------------------------------------------------------------------#

for x in exp/chain/*/decode_{eval,dev}_rescore; do
    [ -d "$x" ] && grep WER "$x"/wer_* | utils/best_wer.sh;
    echo $x
done >> RESULTS

#--------------------------------------------------------------------#
echo " "
echo " ----------- DONE ----------- "
#--------------------------------------------------------------------#
exit 0
#--------------------------------------------------------------------#

