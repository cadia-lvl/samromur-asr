#!/bin/bash -eu
#
# Author: Egill Anton Hlöðversson
# 
# Prepares speech data, extract features, train, and test tdnn-lstm model with Kaldi-ASR.

. ./path.sh
. ./cmd.sh
. ./utils.sh

stage=0;
num_threads=4;
num_jobs=16;
minibatch_size=128;

# Acoustic Data - Notice please check if paths are correct
samromur_root=~/samromur_recordings_1000;
samromur_audio_dir=$samromur_root/audio;
samromur_meta_file=$samromur_root/metadata.tsv;


# TODO: Use instead when ready - Samromur Corpus
# samromur_audio_dir=~/samromur_recordings/audio
# samromur_meta_file=~/samromur_recordings/metadata.tsv

# Language Data - Notice please check if paths are correct
iceandic_pronunciation_dict=$ICELANDIC_PRONDICT_ROOT/frambordabok_asr_v1.txt;


data_train=./data/train;
data_test=./data/test;
training_dataset_ratio=80;

dataset_dir=./audio;

println "Running: $BASH_SOURCE";
start=$SECONDS

# Preparing filesystem
# Creating required files and directories need
if [ $stage -le 0 ]; then
	println "";
	println "### BEGIN PREPARING FILESYSTEM ###";
	timer=$SECONDS;
	
	. ./prep_filesystem.sh
	
	println "### END PREPARING FILESYSTEM ### - Elapsed: $((($SECONDS - timer) / 3600))hrs $(((($SECONDS - timer) / 60) % 60))min $((($SECONDS - timer) % 60))sec";
fi

# Split Samrómur dataset into a training and test set
if [ $stage -le 0 ]; then
	println "";
	println "### BEGIN - SPLITTING DATASET ###";
	timer=$SECONDS;

	if [[ -d $samromur_audio_dir && -f $samromur_meta_file ]]; then
	# Creates /train and /test directories underneath the $dataset_dir directory
	. ./split_dataset.sh $samromur_audio_dir $samromur_meta_file $training_dataset_ratio $dataset_dir;
	fi

	println "### END - SPLITTING DATASET ### - Elapsed: $((($SECONDS - timer) / 3600))hrs $(((($SECONDS - timer) / 60) % 60))min $((($SECONDS - timer) % 60))sec";
fi

# Prepare data
# Prepare acoustic and language data from the Samrómur dataset and the Iceandic pronunciation dictionary
if [ $stage -le 1 ]; then
	println "";
	println "### BEGIN - DATA PREPARATION ###";
	timer=$SECONDS;

	if [[ -d $dataset_dir && -f $iceandic_pronunciation_dict ]]; then
		. ./prep_data.sh $dataset_dir $iceandic_pronunciation_dict;
	fi

	println "### END - DATA PREPARATION ### - Elapsed: $((($SECONDS - timer) / 3600))hrs $(((($SECONDS - timer) / 60) % 60))min $((($SECONDS - timer) % 60))sec";
fi


# Extract MFCC features
# Extract the Mel Frequency Cepstral Coefficient (MFCC) from the training and test data.
if [ $stage -le 2 ]; then
	println "";
	println "### BEGIN - FEATURE EXTRACTION ###";
	timer=$SECONDS;
	
	mfcc_dir=mfcc;

	# Training dataset
	steps/make_mfcc.sh --nj $num_jobs --cmd "$train_cmd" --mfcc-config conf/mfcc.conf "$data_train" exp/make_mfcc/"$data_train" $mfcc_dir || exit 1;
	steps/compute_cmvn_stats.sh "$data_train" \exp/make_mfcc/"$data_train" mfcc;

	# Test dataset
	steps/make_mfcc.sh --nj $num_jobs --cmd "$train_cmd" --mfcc-config conf/mfcc.conf "$data_test" exp/make_mfcc/"$data_test" $mfcc_dir || exit 1;
	steps/compute_cmvn_stats.sh "$data_test" \exp/make_mfcc/"$data_test" mfcc;

	println "### END - FEATURE EXTRACTION - TRAINING SET ### -Elapsed: $((($SECONDS - timer) / 3600))hrs $(((($SECONDS - timer) / 60) % 60))min $((($SECONDS - timer) % 60))sec";
fi

println ""
println "### DONE ###"
println "Total Elapsed: $((($SECONDS - start) / 3600))hrs $(((($SECONDS - start) / 60) % 60))min $((($SECONDS - start) % 60))sec";