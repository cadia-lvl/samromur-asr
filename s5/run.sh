#!/bin/bash -eu
#
# Author: Egill Anton Hlöðversson
# 
# Prepares speech data, extract features, train, and test tdnn-lstm model with Kaldi-ASR.
# 

. ./path.sh
. ./cmd.sh

stage=0
num_threads=4
num_jobs=16
minibatch_size=128

# Acoustic Data - Notice please check if paths are correct
samromur_audio_dir=~/samromur_recordings_1000/audio
samromur_meta_file=~/samromur_recordings_1000/metadata.tsv

# TODO: Use instead when ready - Samromur Corpus
# samromur_audio_dir=~/samromur_recordings/audio
# samromur_meta_file=~/samromur_recordings/metadata.tsv

# Language Data - Notice please check if paths are correct
iceandic_pronunciation_dict=$ICELANDIC_PRONDICT_ROOT/frambordabok_asr_v1.txt

# Our custom print funciton 
println() { printf "$@\n" >&2; }

println "Running: $BASH_SOURCE";
start=$SECONDS

if [[ ! -e "./data" ]]; then
	# If directory doesn't exists, prepare data
	println ""
	println "### BEGIN DATA PREPARATION ###"
	timer=$SECONDS;

	# Prepare Data
	. ./prep_data.sh $samromur_audio_dir $samromur_meta_file $iceandic_pronunciation_dict;

	println ""
	println "### END DATA PREPARATION ### - Elapsed: $((($SECONDS - timer) / 3600))hrs $(((($SECONDS - timer) / 60) % 60))min $((($SECONDS - timer) % 60))sec";
fi

if [ $stage -le 1 ]; then

	println ""
	println "### BEGIN FEATURE EXTRACTION ###"
	timer=$SECONDS;

	mfcc_dir=mfcc;
	data_train=data/train;

	steps/make_mfcc.sh \
		--nj $num_jobs \
		--cmd "$train_cmd" \
		--mfcc-config conf/mfcc.conf \
		"$data_train" \
		exp/make_mfcc/"$data_train" \
		$mfcc_dir || exit 1;

	steps/compute_cmvn_stats.sh "$DATATRAIN" \exp/make_mfcc/"$DATATRAIN" mfcc
	println ""
	println "### END FEATURE EXTRACTION ### -Elapsed: $((($SECONDS - timer) / 3600))hrs $(((($SECONDS - timer) / 60) % 60))min $((($SECONDS - timer) % 60))sec";

fi

if [ $stage -le 2 ]; then
	
	println ""
	println "### BEGIN TESTING ###"
	timer=$SECONDS;
	# steps/make_mfcc.sh --nj $num_jobs --cmd "$train_cmd" --mfcc-config conf/mfcc.conf "$DATATEST" exp/make_mfcc/"$DATATEST" mfcc
	# steps/compute_cmvn_stats.sh "$DATATEST" exp/make_mfcc/"$DATATEST" mfcc

	println ""
	println "### END TESTING ### -Elapsed: $((($SECONDS - timer) / 3600))hrs $(((($SECONDS - timer) / 60) % 60))min $((($SECONDS - timer) % 60))sec";
fi



# if [ $stage -le 2 ]; then
# 	println "Extracting features for test."
# 	steps/make_mfcc.sh --nj $num_jobs --cmd "$train_cmd" --mfcc-config conf/mfcc.conf "$DATATEST" exp/make_mfcc/"$DATATEST" mfcc
# 	steps/compute_cmvn_stats.sh "$DATATEST" exp/make_mfcc/"$DATATEST" mfcc
# fi

# if [ ! -d data/lang ]; then
#     println "Unpacking data/lang.tar.gz"
#     mkdir data/lang
#     tar xzf data/lang.tar.gz -C data
# fi

# if [ ! -d data/lang_bi_small ]; then
#     println "Unpacking data/lang_bi_small.tar.gz"
#     mkdir data/lang_bi_small
#     tar xzf data/lang_bi_small.tar.gz -C data
# fi

# if [ $stage -le 3 ]; then
# 	println "Training LDA MLLT."
# 	./local/train_lda_mllt.sh "$DATATRAIN" "$DATATEST"
# fi

# if [ $stage -le 4 ]; then
# 	println "Preparing tdnn-lstm training"
# 	./local/chain/prepare_tdnn_lstm.sh
# fi

# if [ $stage -le 5 ]; then
# 	println "Training tdnn-lstm model"
# 	./local/online/run_tdnn_lstm.sh
# fi


# if [ $stage -le 6 ]; then
# 	println "Decoding test set using tdnn-lstm trained data"
# 	./local/decode_tdnn_lstm.sh "$DATATEST" exp/chain/tdnn_lstm/graph_bi_small

# 	println "Scoring decoding results"
# 	./local/score.sh --cmd "$decode_cmd" "$DATATEST" exp/chain/tdnn_lstm/graph_bi_small exp/chain/tdnn_lstm/decode_{$DATATEST}
# fi

println ""
println "### DONE ###"
println "Total Elapsed: $((($SECONDS - start) / 3600))hrs $(((($SECONDS - start) / 60) % 60))min $((($SECONDS - start) % 60))sec";