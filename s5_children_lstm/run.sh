#!/usr/bin/env bash
#--------------------------------------------------------------------#
# Copyright   2021 Reykjavik University (Authors: Carlos Daniel 
#Hernández Mena - carlosm@ru.is)

#Based on a previous recipe by: Judy Fong - judyfong@ru.is, 
#Inga Run Helgadottir - ingarun@ru.is and 
#Michal Borsky - michalb@ru.is

#--------------------------------------------------------------------#
# Apache 2.0
#
# See ../README.txt for more info on data required.
#SBATCH --output=logs/samrun%J.out
#SBATCH --nodelist=terra

#--------------------------------------------------------------------#
#INSTALL THIS:
#sudo apt-get install flac
#sudo apt install libfst-tools
#pip install pandas
#--------------------------------------------------------------------#
#TYPE THIS:
#sudo nvidia-smi -c 3

#--------------------------------------------------------------------#
this_script="run.sh"
echo " "
echo "+++++++++++++++++++++++++++++++++++++++++++++"
echo "INFO ($this_script): Starting the Recipe"
date
echo "+++++++++++++++++++++++++++++++++++++++++++++"
echo " "

#--------------------------------------------------------------------#
# To be run from the s5_adolescents directory

echo "-----------------------------------"
echo "Initialization ..."
echo "-----------------------------------"

#--------------------------------------------------------------------#
#Setting up important paths and variables
#--------------------------------------------------------------------#
# NOTE! In the future the ASR data, LM training text and pronunciation 
#dictionary will be downloaded from online first, e.g. Clarin

corpus_root=<path-to-the-corpus>/samromur_children_ldc

prondict_orig=<path-to-the-dictionary>/ICELANDIC_PRONUNCIATION_DICTIONARY.dic

arpa_lm_3g=<path-to-the-language_model>/3GRAM_ARPA_MODEL_PRUNED.lm
arpa_lm_4g=<path-to-the-language_model>/4GRAM_ARPA_MODEL.lm

featdir="feat"

#--------------------------------------------------------------------#
#CONTROL PANEL
#--------------------------------------------------------------------#
from_stage=0
to_stage=14

nj_train=14 #30
nj_decode=8 #32
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

#Inform to the user
echo " "
echo "INFO ($this_script): Initialization Done!"
echo " "

#--------------------------------------------------------------------#
#Verifiying that some important files are in place.
#--------------------------------------------------------------------#

[ ! -d "$corpus_root" ] && echo "$0: expected $corpus_root to exist" && exit 1;

for f in "$arpa_lm_3g" "$arpa_lm_4g" "$prondict_orig"; do \
    [ ! -f $f ] && echo "$0: expected $f to exist" && exit 1;
done

#--------------------------------------------------------------------#
#Data Preparation
#--------------------------------------------------------------------#
current_stage=0
if  [ $current_stage -ge $from_stage ] && [ $current_stage -le $to_stage ]; then
    echo "-----------------------------------"
    echo "Stage $current_stage: Create ./data directories"
    echo "-----------------------------------"
    
    #This script creates the files:
    #spk2gender, text, utt2spk and wav.scp
    python3 local/samromur_children_data_prep.py $corpus_root
    
    for dir in train test dev; do
        #Kaldi script for creating the file: spk2utt
        utils/utt2spk_to_spk2utt.pl data/$dir/utt2spk > data/$dir/spk2utt
        
        #Kaldi script for fixing the format of the 
        #files in the data dir.
        utils/fix_data_dir.sh data/$dir
    done
    
    echo " "
    echo "INFO ($this_script): Stage $current_stage Done!"
    echo " "
fi

#--------------------------------------------------------------------#
#MFCC Calculation
#--------------------------------------------------------------------#
current_stage=1
if  [ $current_stage -ge $from_stage ] && [ $current_stage -le $to_stage ]; then
    echo "-----------------------------------"
    echo "Stage $current_stage: Make MFCCs"
    echo "-----------------------------------"
    
    for name in train test dev; do
        steps/make_mfcc.sh \
        --mfcc-config conf/mfcc.conf \
        --nj $nj_train --cmd "$train_cmd" \
        data/$name exp/make_mfcc $featdir \
        || error 1 "Failed creating MFCC features";
    done
    
    echo " "
    echo "INFO ($this_script): Stage $current_stage Done!"
    echo " "
fi

#--------------------------------------------------------------------#
#Computing Cepstral Mean and Variance Normalization statistics (CMVN)
#--------------------------------------------------------------------#
current_stage=2
if  [ $current_stage -ge $from_stage ] && [ $current_stage -le $to_stage ]; then
    echo "-----------------------------------"
    echo "Stage $current_stage: Compute CMVN"
    echo "-----------------------------------"
    
    for name in train test dev; do
        steps/compute_cmvn_stats.sh \
        data/$name exp/make_mfcc $featdir
        
        utils/validate_data_dir.sh data/"$name" || utils/fix_data_dir.sh data/"$name" || exit 1;
    done
    
    echo " "
    echo "INFO ($this_script): Stage $current_stage Done!"
    echo " "
fi

#--------------------------------------------------------------------#
#Coping prefabricated files
#--------------------------------------------------------------------#
current_stage=3
if  [ $current_stage -ge $from_stage ] && [ $current_stage -le $to_stage ]; then
    echo "-----------------------------------"
    echo "Stage $current_stage: Copying prefabricated files"
    echo "-----------------------------------"
    
    mkdir -p data/local
    mkdir -p data/local/dict
    
    cp local/Prefabricated_Files/nonsilence_phones.txt data/local/dict/nonsilence_phones.txt
    cp local/Prefabricated_Files/optional_silence.txt data/local/dict/optional_silence.txt
    cp local/Prefabricated_Files/silence_phones.txt data/local/dict/silence_phones.txt
    cp local/Prefabricated_Files/extra_questions.txt data/local/dict/extra_questions.txt
    
    echo " "
    echo "INFO ($this_script): Stage $current_stage Done!"
    echo " "
fi

#--------------------------------------------------------------------#
#Create the lexicon
#--------------------------------------------------------------------#
current_stage=4
if  [ $current_stage -ge $from_stage ] && [ $current_stage -le $to_stage ]; then
    echo "-----------------------------------"
    echo "Stage $current_stage: Create the lexicon"
    echo "-----------------------------------"
    
    python3 local/create_lexicon.py $prondict_orig

    mkdir -p data/lang
    mkdir -p data/lang/phones

    utils/prepare_lang.sh data/local/dict "<UNK>" data/local/lang data/lang
    
    echo " "
    echo "INFO ($this_script): Stage $current_stage Done!"
    echo " "
fi

#--------------------------------------------------------------------#
#Prepare the 3-Gram language model
#--------------------------------------------------------------------#
current_stage=5
if  [ $current_stage -ge $from_stage ] && [ $current_stage -le $to_stage ]; then
    echo "-----------------------------------"
    echo "Stage $current_stage: Preparing the 3-gram language model"
    echo "-----------------------------------"
    
    lang_target_dir=data/lang_3g
    lm_compressed=srilm_3g_pruned_arpa.gz
    lm_in=$arpa_lm_3g
    
    mkdir -p $lang_target_dir
    
    #If the LM is already compressed, it won't be compressed again.
    if [ ! -f $lang_target_dir/$lm_compressed ]; then
        gzip -c $arpa_lm_3g > $lang_target_dir/$lm_compressed
    fi
    
    #If the file G.fst exists, it won't be created again.
    if [ ! -f $lang_target_dir/G.fst ]; then
        #utils/format_lm.sh: Converts ARPA-format language models to FSTs.
        utils/format_lm.sh data/lang $lang_target_dir/$lm_compressed data/local/dict/lexicon.txt $lang_target_dir
    fi
    
    echo " "
    echo "INFO ($this_script): Stage $current_stage Done!"
    echo " "
fi

#--------------------------------------------------------------------#
#Prepare the 4-Gram language model
#--------------------------------------------------------------------#
current_stage=6
if  [ $current_stage -ge $from_stage ] && [ $current_stage -le $to_stage ]; then
    echo "-----------------------------------"
    echo "Stage $current_stage: Preparing the 4-gram language model"
    echo "-----------------------------------"

    lang_target_dir=data/lang_4g
    lm_compressed=srilm_4g_unpruned_arpa.gz
    lm_in=$arpa_lm_4g
    
    mkdir -p $lang_target_dir
    
    #If the LM is already compressed, it won't be compressed again.
    if [ ! -f $lang_target_dir/$lm_compressed ]; then
        gzip -c $lm_in > $lang_target_dir/$lm_compressed
    fi
    
    #If the file G.fst exists, it won't be created again.
    if [ ! -f $lang_target_dir/G.fst ]; then
        #utils/format_lm.sh: Converts ARPA-format language models to FSTs.
        utils/format_lm.sh data/lang $lang_target_dir/$lm_compressed data/local/dict/lexicon.txt $lang_target_dir
    fi
    
    #If the file G.carpa exists, it won't be created again.
    if [ ! -f $lang_target_dir/G.carpa ]; then 
        utils/build_const_arpa_lm.sh $lang_target_dir/$lm_compressed data/lang $lang_target_dir
    fi
    
    echo " "
    echo "INFO ($this_script): Stage $current_stage Done!"
    echo " "
fi

#--------------------------------------------------------------------#
#Train a monophone system
#--------------------------------------------------------------------#
current_stage=7
if  [ $current_stage -ge $from_stage ] && [ $current_stage -le $to_stage ]; then
    echo "-----------------------------------"
    echo "Stage $current_stage: Train monophone system"
    echo "-----------------------------------"
    
    steps/train_mono.sh \
    --nj $nj_train \
    --cmd "$train_cmd" \
    --boost-silence 1.25 \
    data/train data/lang exp/mono

    echo "-----------------------------------"    
    echo "Stage $current_stage: Mono alignment. Align to mono"
    echo "-----------------------------------"
    steps/align_si.sh \
    --nj $nj_train --cmd "$train_cmd" \
    data/train data/lang \
    exp/mono exp/mono_ali
    
    echo "-----------------------------------"
    echo "Stage $current_stage: First triphone on train, delta + delta-delta features"
    echo "-----------------------------------"
    steps/train_deltas.sh \
    --cmd "$train_cmd" \
    2000 10000 \
    data/train data/lang \
    exp/mono_ali exp/tri1
    
    echo " "
    echo "INFO ($this_script): Stage $current_stage Done!"
    echo " "
fi

#--------------------------------------------------------------------#
#LDA/MLLT Training
#--------------------------------------------------------------------#
current_stage=8
if  [ $current_stage -ge $from_stage ] && [ $current_stage -le $to_stage ]; then
    echo "-----------------------------------"
    echo "Stage $current_stage: Aligning the train set to tri1"
    echo "-----------------------------------"
    
    steps/align_si.sh \
    --nj $nj_train \
    --cmd "$train_cmd" \
    data/train data/lang \
    exp/tri1 exp/tri1_ali

    echo "-----------------------------------"
    echo "Stage $current_stage: Train LDA + MLLT"
    echo "-----------------------------------"
    steps/train_lda_mllt.sh \
    --cmd "$train_cmd"  \
    4000 40000 data/train \
    data/lang exp/tri1_ali exp/tri2
    
    echo " "
    echo "INFO ($this_script): Stage $current_stage Done!"
    echo " "
fi

#--------------------------------------------------------------------#
#LDA/MLLT/SAT Training
#--------------------------------------------------------------------#
current_stage=9
if  [ $current_stage -ge $from_stage ] && [ $current_stage -le $to_stage ]; then

    echo "-----------------------------------"
    echo "Stage $current_stage: Aligning the full training set to tri2"
    echo "-----------------------------------"
    steps/align_fmllr.sh \
    --nj $nj_train \
    --cmd "$train_cmd" \
    data/train data/lang \
    exp/tri2 exp/tri2_ali
    
    echo "-----------------------------------"
    echo "Stage $current_stage: Train LDA + MLLT + SAT"
    echo "-----------------------------------"
    steps/train_sat.sh --cmd "$train_cmd"  4000 40000 data/train \
    data/lang exp/tri2_ali exp/tri3
    
    echo " "
    echo "INFO ($this_script): Stage $current_stage Done!"
    echo " "
fi

#--------------------------------------------------------------------#
#Decoding Graph
#--------------------------------------------------------------------#
current_stage=10
if  [ $current_stage -ge $from_stage ] && [ $current_stage -le $to_stage ]; then
    echo "-----------------------------------"
    echo "Stage $current_stage: Make decoding graph."
    echo "-----------------------------------"
    utils/mkgraph.sh \
    data/lang_3g exp/tri3 \
    exp/tri3/graph

    echo " "
    echo "INFO ($this_script): Stage $current_stage Done!"
    echo " "
fi

#--------------------------------------------------------------------#
#Triphone decoding
#--------------------------------------------------------------------#
current_stage=11
if  [ $current_stage -ge $from_stage ] && [ $current_stage -le $to_stage ]; then

    dir=test
    echo "-----------------------------------"
    echo "Stage $current_stage: FMLLR Decoding (for $dir)"
    echo "-----------------------------------"
    steps/decode_fmllr.sh \
    --config conf/decode.config \
    --nj "$nj_decode"  \
    --cmd "$decode_cmd" \
    exp/tri3/graph data/$dir \
    exp/tri3/decode_$dir;
        
    echo "-----------------------------------"
    echo "Stage $current_stage: LM Rescoring (for $dir)"
    echo "-----------------------------------"
    steps/lmrescore_const_arpa.sh \
    --cmd "$decode_cmd" \
    data/lang_{3g,4g} data/$dir \
    exp/tri3/decode_$dir \
    exp/tri3/decode_${dir}_rescored

    dir=dev
    echo "-----------------------------------"
    echo "Stage $current_stage: FMLLR Decoding (for $dir)"
    echo "-----------------------------------"
    steps/decode_fmllr.sh \
    --config conf/decode.config \
    --nj "$nj_decode"  \
    --cmd "$decode_cmd" \
    exp/tri3/graph data/$dir \
    exp/tri3/decode_$dir;
        
    echo "-----------------------------------"
    echo "Stage $current_stage: LM Rescoring (for $dir)"
    echo "-----------------------------------"
    steps/lmrescore_const_arpa.sh \
    --cmd "$decode_cmd" \
    data/lang_{3g,4g} data/$dir \
    exp/tri3/decode_$dir \
    exp/tri3/decode_${dir}_rescored

    echo " "
    echo "INFO ($this_script): Stage $current_stage Done!"
    echo " "
fi

#--------------------------------------------------------------------#
#Report WER Results from the HMM mmodel.
#--------------------------------------------------------------------#
current_stage=12
if  [ $current_stage -ge $from_stage ] && [ $current_stage -le $to_stage ]; then

    echo "-----------------------------------"
    echo "Stage $current_stage: Writing Results in a text file"    
    echo "-----------------------------------"

    for x in exp/*/decode_{test,dev}_rescored; do
        [ -d "$x" ] && grep WER "$x"/wer_* | utils/best_wer.sh;
    done > RESULTS
    
    echo " "
    echo "INFO ($this_script): Stage $current_stage Done!"
    echo " "
fi

#--------------------------------------------------------------------#
#TDNN-LSTM
#--------------------------------------------------------------------#
current_stage=13
if  [ $current_stage -ge $from_stage ] && [ $current_stage -le $to_stage ]; then
    echo "-----------------------------"
    echo "Stage $current_stage: TDNN-LSTM Training"
    echo "-----------------------------"
    
    #The stages goes from 14 to 20 but the default value is 0
    local/chain/run_tdnn_lstm_ADAPTED.sh --stage 0 --train-set train --gmm tri3 --nnet3-affix ""
    wait
    
    echo " "
    echo "INFO ($this_script): Stage $current_stage Done!"
    echo " "
fi

#--------------------------------------------------------------------#
#Report WER Results from the LSTM Network
#--------------------------------------------------------------------#
current_stage=14
if  [ $current_stage -ge $from_stage ] && [ $current_stage -le $to_stage ]; then
    echo "-----------------------------"
    echo "Stage $current_stage: Printing the TDNN-LSTM WER Results"
    echo "-----------------------------"
    
    #Writing Results in a text file
    for x in exp/chain/*/decode_{test,dev}_rescore; do
        [ -d "$x" ] && grep WER "$x"/wer_* | utils/best_wer.sh;
        echo $x
    done >> RESULTS
    
    echo " "
    echo "INFO ($this_script): Stage $current_stage Done!"
    echo " "
fi

#--------------------------------------------------------------------#
echo " "
echo "+++++++++++++++++++++++++++++++++++++++++++++"
echo "INFO ($this_script): All Stages Done Successfully!"
date
echo "+++++++++++++++++++++++++++++++++++++++++++++"
echo " "
#--------------------------------------------------------------------#

