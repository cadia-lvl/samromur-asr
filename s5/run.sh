#!/bin/bash -eu
#
# Authors: Egill Anton Hlöðversson,
#		   David Erik Mollberg
#	 
# Prepares speech data, extract features, train, and test tdnn-lstm model with Kaldi-ASR.

. ./path.sh
. ./cmd.sh
. ./utils.sh

#Settings
stage=1;
num_threads=4;
num_jobs=10;
minibatch_size=128;
training_dataset_ratio=80;

dataset_dir=./audio;
data_train=./data/train;
data_test=./data/test;

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
	println "### Stage 0: BEGIN - SPLITTING DATASET ###";
	timer=$SECONDS;

	if [[ -d $SAMROMUR_AUDIO && -f $SAMROMUR_META ]]; 
	then
		# Creates /train and /test directories underneath the $dataset_dir directory
		. ./split_dataset.sh $SAMROMUR_AUDIO $SAMROMUR_META $training_dataset_ratio $dataset_dir;
	else
		println "File error. Can't find $SAMROMUR_AUDIO or $SAMROMUR_META. Check path.sh";
	fi
	

	println "### Stage 0: END - SPLITTING DATASET ### - Elapsed: $((($SECONDS - timer) / 3600))hrs $(((($SECONDS - timer) / 60) % 60))min $((($SECONDS - timer) % 60))sec";
fi

# Prepare data
# Prepare acoustic and language data from the Samrómur dataset and the Iceandic pronunciation dictionary
# Todo add LM creation in Stage 1
if [ $stage -le 1 ]; then
	println "";
	println "### Stage 1: BEGIN - DATA PREPARATION ###";
	timer=$SECONDS;

	if [[ -d $dataset_dir && -f $ICELANDIC_PRONDICT && -f $CORPUS ]]; 
	then
		#. ./prep_data.sh $dataset_dir $ICELANDIC_PRONDICT;
		. ./create_lm.sh $CORPUS
	else
		println "File error. Can't find $dataset_dir, $ICELANDIC_PRONDICT or $CORPUS. Check path.sh";
	fi

	println "### Stage 1: END - DATA PREPARATION ### - Elapsed: $((($SECONDS - timer) / 3600))hrs $(((($SECONDS - timer) / 60) % 60))min $((($SECONDS - timer) % 60))sec";
fi


# Extract MFCC features
# Extract the Mel Frequency Cepstral Coefficient (MFCC) from the training and test data.
if [ $stage -le 2 ]; then
	println "";
	println "### Stage 2: BEGIN - FEATURE EXTRACTION ###";
	timer=$SECONDS;
	
	mfcc_dir=mfcc;

	# Training dataset
	steps/make_mfcc. 

	# Test dataset
	steps/make_mfcc.sh --nj $num_jobs --cmd "$train_cmd" --mfcc-config conf/mfcc.conf "$data_test" exp/make_mfcc/"$data_test" $mfcc_dir || exit 1;
	steps/compute_cmvn_stats.sh "$data_test" \exp/make_mfcc/"$data_test" mfcc;

	println "### Stage 2: END - FEATURE EXTRACTION ### -Elapsed: $((($SECONDS - timer) / 3600))hrs $(((($SECONDS - timer) / 60) % 60))min $((($SECONDS - timer) % 60))sec";
fi

# Train an acoustic model, LDA+MLLT triphoness
if [ $stage -le 3 ]; then
	println "";
	println "### Stage 3: BEGIN - TRAIN THE ACOUTSTIC MODEL ###";

	echo "Training LDA MLLT."
	./train_lda_mllt.sh "$data_train" "$data_test"
	
	println "### Stage 3: END - TRAIN THE ACOUTSTIC MODEL ### -Elapsed: $((($SECONDS - timer) / 3600))hrs $(((($SECONDS - timer) / 60) % 60))min $((($SECONDS - timer) % 60))sec";

fi



println ""
println "### DONE ###"
println "Total Elapsed: $((($SECONDS - start) / 3600))hrs $(((($SECONDS - start) / 60) % 60))min $((($SECONDS - start) % 60))sec";