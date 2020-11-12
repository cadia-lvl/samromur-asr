#!/bin/bash -e
#
# Author: Egill Anton Hlöðversson, Inga Rún Helgadóttir
#
# Prepares audio and language data, extract features, train, and test tdnn-lstm model with Kaldi-ASR.

set -o pipefail

stage=0;
num_jobs=20
nj_decode=32
decode_num_threads=4

. ./path.sh
. ./cmd.sh
. ./utils.sh

if [ "$1" == "-h" ]; then
    echo "Prepares audio and language data, extract features, train, and test"
    echo "a tdnn-lstm model with Kaldi-ASR."
    echo "Usage: $(basename $0) [-h]"
    exit 0
fi

# Acoustic Data - Notice please check if paths are correct
samromur_root=/data/samromur/samromur_v1/samromur_v1/
samromur_audio_dir=$samromur_root/audio;
samromur_meta_file=$samromur_root/metadata_extended.tsv;

outdir=/work/inga/h7
exp="$outdir"/exp
data="$outdir"/data
mfcc="$outdir"/mfcc
mfcc_hires="$outdir"/mfcc_hires

# Note I need to update all the following
# since we won't use any of the current data/models
# Newest pronunciation dictionary
prondict=/data/althingi/data/lexicon/prondict.20190411.txt #$(ls -t "$root_lexicon"/prondict.* | head -n1)
localdict=$outdir/data/local #/work/inga/mallyskur_eydis/data/local/dict_rmh_2020-08-11/dict
lmdir=/models/althingi/language_model/20190114/ #/work/inga/mallyskur_eydis/data/lang_rmh_2020-08-11
lang=$lmdir/lang
#lm_trainingset=/work/inga/mallyskur_eydis/data/lm_training_text/base_2020-08-11.txt
mkdir -p "$lmdir"/log $localdict

for f in "$samromur_audio_dir" "$samromur_meta_file" "$prondict"; do
    [ ! -f "$f" ] && echo "$0: expected $f to exist" && exit 1;
done

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

if [ -L steps ] && [ -L utils ]; then
    echo "steps and utils exist"
else
    echo "Create steps and utils symlinks before running"
    ln -sfn "$KALDI_ROOT"/egs/wsj/s5/steps steps
    ln -sfn "$KALDI_ROOT"/egs/wsj/s5/utils utils
fi

println "Running: $BASH_SOURCE"
start=$SECONDS

echo "Create the Kaldi files: wav.scp, text, utt2spk and spk2utt"
if [ $stage -le 1 ]; then
    println "";
    println "### BEGIN - DATA PREPARATION ###";
    timer=$SECONDS;
    
    if [[ -d $samromur_audio_dir && -f $samromur_meta_file ]]; then
        python3 local/samromur_prep_data.py $samromur_audio_dir $samromur_meta_file $data
    fi
    
    println "### END - DATA PREPARATION ### - Elapsed: $(((SECONDS - timer) / 3600))hrs $((((SECONDS - timer) / 60) % 60))min $(((SECONDS - timer) % 60))sec";
fi


echo "Extract MFCC features"
# Extract the Mel Frequency Cepstral Coefficient (MFCC) from the training and test data.
if [ $stage -le 2 ]; then
    println "";
    println "### BEGIN - FEATURE EXTRACTION ###";
    timer=$SECONDS;
    
    for i in train eval test ; do
        steps/make_mfcc.sh \
        --nj $num_jobs \
        --cmd "$train_cmd" \
        --mfcc-config conf/mfcc.conf \
        "$data/$i" $exp/make_mfcc $mfcc || exit 1;
    done
    
    for i in train eval test ; do
        echo "Computing cmvn stats"
        steps/compute_cmvn_stats.sh \
        "$data/$i" $exp/make_mfcc $mfcc;
        
        utils/validate_data_dir.sh "$data/$i" \
        || utils/fix_data_dir.sh "$data"/"$i" || exit 1;
    done
    
    println "";
    println "### END - FEATURE EXTRACTION ### -Elapsed: $(((SECONDS - timer) / 3600))hrs $((((SECONDS - timer) / 60) % 60))min $(((SECONDS - timer) % 60))sec";
fi


# if [ $stage -le 3 ]; then

#     if [ ! -d "$lang" ]; then
#         echo "Create the lexicon"
#         [ -d $localdict ] && rm -r $localdict
#         mkdir -p $localdict "$lang"
#         local/prep_lang.sh \
#         $prondict        \
#         $localdict   \
#         "$lang"
#     fi

#     echo "Preparing a pruned trigram language model"
#     utils/slurm.pl --mem 16G "$lmdir"/log/make_LM_3gsmall.log \
#     local/make_LM.sh \
#     --order 3 --small true --carpa false \
#     $lm_trainingset "$lang" \
#     $localdict/lexicon.txt "$lmdir" \
#     || error 1 "Failed creating a pruned trigram language model"


#     echo "Preparing an unpruned 4g LM"
#     utils/slurm.pl --mem 20G "$lmdir"/log/make_LM_4g.log \
#     local/make_LM.sh \
#     --order 4 --small false --carpa true \
#     $lm_trainingset "$lang" \
#     $localdict/lexicon.txt "$lmdir" \
#     || error 1 "Failed creating an unpruned 4-gram language model"

#     echo "Make a zerogram language model to be able to check the effect of"
#     echo "the language model in the ASR results"
#     utils/slurm.pl "$lmdir"/log/make_zerogram_LM.log \
#     local/make_zgLM.sh \
#     "$lang" $localdict/lexicon.txt "$lmdir"/lang_zg \
#     || error 1 "Failed creating a zerogram language model"

# fi

if [ $stage -le 4 ]; then
    echo "Make subsets of the training data to use for the first mono and triphone trainings"
    
    utils/subset_data_dir.sh $data/train 40000 $data/train_40k
    utils/subset_data_dir.sh --shortest $data/train_40k 5000 $data/train_5kshort
    utils/subset_data_dir.sh $data/train 10000 $data/train_10k
    utils/subset_data_dir.sh $data/train 20000 $data/train_20k
    
fi

# Note! Read the following over. I made some changes since I'm using Roberts
# models in the first test. $lang should be $lmdir/lang
if [ $stage -le 5 ]; then
    
    echo "Train a mono system"
    steps/train_mono.sh    \
    --nj $num_jobs           \
    --cmd "$train_cmd" \
    --totgauss 4000    \
    $data/train_5kshort \
    $lang          \
    $exp/mono
    
    echo "mono alignment. Align train_10k to mono"
    steps/align_si.sh \
    --nj $num_jobs --cmd "$train_cmd" \
    $data/train_10k $lang $exp/mono $exp/mono_ali
    
    echo "first triphone training"
    steps/train_deltas.sh  \
    --cmd "$train_cmd" \
    2000 10000         \
    $data/train_10k $lang $exp/mono_ali $exp/tri1
    
fi

if [ $stage -le 6 ]; then
    echo "First triphone decoding"
    utils/mkgraph.sh $lmdir/lang_3gsmall $exp/tri1 $exp/tri1/graph
    
    for dir in eval test; do
        (
            steps/decode.sh \
            --config conf/decode.config \
            --nj "$nj_decode" --cmd "$decode_cmd" \
            $exp/tri1/graph $data/$dir \
            $exp/tri1/decode_$dir;
            
            steps/lmrescore_const_arpa.sh \
            --cmd "$decode_cmd" \
            $lmdir/lang_{3gsmall,5g} $data/$dir \
            $exp/tri1/decode_$dir \
            $exp/tri1/decode_${dir}_rescored
        ) &
    done
    wait
    
fi


if [ $stage -le 7 ]; then
    echo "Aligning train_20k to tri1"
    steps/align_si.sh \
    --nj $num_jobs --cmd "$train_cmd" \
    $data/train_20k $lang \
    $exp/tri1 $exp/tri1_ali
    
    echo "Training LDA+MLLT system tri2"
    steps/train_lda_mllt.sh \
    --cmd "$train_cmd" \
    --splice-opts "--left-context=3 --right-context=3" \
    3000 25000 \
    $data/train_20k $lang \
    $exp/tri1_ali $exp/tri2
    
fi

if [ $stage -le 8 ]; then
    echo "Second triphone decoding"
    utils/mkgraph.sh $lmdir/lang_3gsmall $exp/tri2 $exp/tri2/graph
    
    for dir in eval test; do
        (
            steps/decode.sh \
            --config conf/decode.config \
            --nj "$nj_decode" --cmd "$decode_cmd" \
            $exp/tri2/graph $data/$dir \
            $exp/tri2/decode_$dir;
            
            steps/lmrescore_const_arpa.sh \
            --cmd "$decode_cmd" \
            $lmdir/lang_{3gsmall,5g} $data/$dir \
            $exp/tri2/decode_$dir \
            $exp/tri2/decode_${dir}_rescored
        ) &
    done
    wait
    
fi

if [ $stage -le 9 ]; then
    echo "Aligning train_40k to tri2"
    steps/align_si.sh \
    --nj $num_jobs --cmd "$train_cmd" \
    $data/train_40k $lang \
    $exp/tri2 $exp/tri2_ali
    
    echo "Train LDA + MLLT + SAT"
    steps/train_sat.sh    \
    --cmd "$train_cmd" \
    4000 40000    \
    $data/train_40k $lang     \
    $exp/tri2_ali $exp/tri3
    
fi

if [ $stage -le 10 ]; then
    echo "Third triphone decoding"
    utils/mkgraph.sh $lmdir/lang_3gsmall $exp/tri3 $exp/tri3/graph
    
    for dir in eval test; do
        (
            steps/decode_fmllr.sh \
            --config conf/decode.config \
            --nj "$nj_decode" --cmd "$decode_cmd" \
            $exp/tri3/graph $data/$dir \
            $exp/tri3/decode_$dir;
            
            steps/lmrescore_const_arpa.sh \
            --cmd "$decode_cmd" \
            $lmdir/lang_{3gsmall,5g} $data/$dir \
            $exp/tri3/decode_$dir \
            $exp/tri3/decode_${dir}_rescored
        ) &
    done
    wait
fi

if [ $stage -le 11 ]; then
    echo "Aligning train to tri3"
    steps/align_fmllr.sh \
    --nj $num_jobs --cmd "$train_cmd" \
    $data/train $lang \
    $exp/tri3 $exp/tri3_ali
    
    echo "Train SAT again, now on the whole training set"
    steps/train_sat.sh    \
    --cmd "$train_cmd" \
    5000 50000    \
    $data/train $lang     \
    $exp/tri3_ali $exp/tri4
    
fi

if [ $stage -le 12 ]; then
    echo "4th triphone decoding"
    utils/mkgraph.sh $lmdir/lang_3gsmall $exp/tri4 $exp/tri4/graph
    
    for dir in eval test; do
        (
            steps/decode_fmllr.sh \
            --config conf/decode.config \
            --nj "$nj_decode" --cmd "$decode_cmd" \
            --num-threads $decode_num_threads \
            $exp/tri4/graph $data/$dir \
            $exp/tri4/decode_$dir;
            
            steps/lmrescore_const_arpa.sh \
            --cmd "$decode_cmd" \
            $lmdir/lang_{3gsmall,5g} \
            $data/${dir} $exp/tri4/decode_$dir \
            $exp/tri4/decode_${dir}_rescored
        ) &
    done
    wait
fi


println ""
println "### DONE ###"
println "Total Elapsed: $(((SECONDS - start) / 3600))hrs $((((SECONDS - start) / 60) % 60))min $(((SECONDS - start) % 60))sec";
