#!/bin/bash -eu
#
# Author: Egill Anton Hlöðversson
# 
# Prepares speech data from the Samrómur speech corpus for training an Accoustic model in Kaldi-ASR.
# 
# The format of the input info file (e.g. metadata.txt) this script expects (tab-separated columns):
#
# <id>	<filename>	<sex>	<age>	<native-language>	<duration>	<sample-rate>	<sentence>
#
# e.g:
# 12345	bc78cbe8-673f-4250-8fb2-ac63bc8c14ba.wav	female	20-29	Icelandic	1.2	48000	Halló heimur.
#
# Input: a directory of audio files, an info file describing the audio files
# Output: a directory containing all necessary files to start processing by Kaldi
#

# Unicode characters
uc_check_mark="\xe2\x9c\x94";
uc_cross_mark="\xe2\x9c\x96";
uc_attention_mark="\xE2\x9D\x97";
uc_add="\xE2\x9E\x95";
uc_minus="\xE2\x9E\x96";
uc_stars="\xe2\x9c\xa8";

# Our custom print funciton 
println() { printf "$@\n" >&2; }

println "Started running: $0";
SECONDS=0;

sample_rate=16000;
samromur=$(readlink -f $1);
info_file=$2;
output_dir=$3;
train_dir="$3/train/";
train_dir=${train_dir//\/\//\/};
test_dir="$3/test/";
test_dir=${test_dir//\/\//\/};


# Checking input
println "Checking input:";

## Check number of input arguments
if [[ $# != 3 ]]; then
    println "Usage: $0 <path-to-samromur-audio> <info-file-training> <out-data-dir>"
    exit 1;
else
	println "\t$uc_check_mark Number of arguments"
fi

## Check input argument types
# TODO: Check if third argument is a file directory even though it hasnt been created
if [[ ! -d $1 || ! -f $2 ]]; then
	println "$uc_attention_mark Error: Invalid argument type.";
	println "Usage: $0 <path-to-samromur-audio> <info-file-training> <out-data-dir>";
	println "\t<path-to-samromur-audio> : File directory";
	println "\t<info-file-training> : File";
	println "\t<out-data-dir> : File directory";
	
	exit 1;
else
	println "\t$uc_check_mark Argument types"
fi

# Prepearing filesystem 
println "Prepearing filesystem:";

for dir in $output_dir $train_dir $test_dir; do
	if [[ ! -e $dir ]]; then
		mkdir $dir;
		println "\t$uc_add Directory created: $dir";
	else
		println "\t$uc_check_mark $dir";
	fi
done

# TODO: Create spk2gender

# TODO: Create wav.scp

# TODO: Create text

# TODO: Create utt2spk

# TODO: Create corpus.txt


println "Elapsed: $(($SECONDS / 3600))hrs $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec";
