#!/bin/bash -eu
#
# Author: Egill Anton Hlöðversson
# 
# Splits a dataset into train/test set for Kaldi-ASR
# Made for Samrómur-ASR dataset
# Example of usage
# ./split_dataset.sh ~/samromur_recordings_1000/audio/ ~/samromur_recordings_1000/metadata.tsv 80 ~/samromur_recordings_1000

# Unicode characters
uc_check_mark="\xe2\x9c\x94";
uc_cross_mark="\xe2\x9c\x96";
uc_attention_mark="\xE2\x9D\x97";
uc_add="\xE2\x9E\x95";
uc_minus="\xE2\x9E\x96";
uc_stars="\xe2\x9c\xa8";

# Our custom print funciton 
println() { printf "$@\n" >&2; }
path() { eval ${$@/text//\/\//\/}; }

println "Running: $BASH_SOURCE";

start=$SECONDS

println ""
println "Checking Input:";

# Check number of input arguments
if [[ $# != 4 ]]; then
	println "Usage: $0 <path-to-samromur-audio> <path-to-samromur-meta-file> <training-set-split-ratio> <output> ";
	exit 1;
else
	println "\t$uc_check_mark Number of arguments"
fi

# Checking argument types
if [[ ! -d $1 || ! -f $2 || ! -n $3 || ! -d $4 ]]; then
	println "$uc_attention_mark Error: Invalid argument type.";
	println "Usage: $0 <path-to-samromur-audio-directory> <path-to-samromur-meta-file> <training-set-split-ratio>";
	println "\t<path-to-samromur-audio> : File directory";
	println "\t<info-file-training> : File";
	println "\t<training-set-split-ratio> : Integer";
	println "\t<output> : File directory";

	exit 1;
else
	println "\t$uc_check_mark Argument types";
fi

# Get input
data_set=$(readlink -f $1);
meta_file=$2;
traing_set_ratio=$3;
output_dir=$4;

metadata_train=$output_dir/"metadata_train.tsv";
metadata_test=$output_dir/"metadata_test.tsv";

# Preparing filesystem
println ""
println "Preparing Filesystem:";

# Create files
for file in $metadata_train $metadata_test; do
	## Check if file already exists
	if [[ ! -e $file ]]; then
		### If not, create new file
		touch $file;
		println "\t$uc_add File created: $file";
	else
		### Else, clear the content of the file
		> $file;
		println "\t$uc_check_mark $file";
	fi
done

# Create file directories
for dir in $output_dir $output_dir/train $output_dir/test; do
	## Check if directory already exists
	if [[ ! -e $dir ]]; then
		### If not, create new directory
		mkdir $dir;
		println "\t$uc_add Directory created: $dir";
	else
		### Else, do nothing
		println "\t$uc_check_mark $dir";
	fi
done

# Calculate the split
data_set_size=$(ls -1 $1 | wc -l);
let training_set_size=$data_set_size*$traing_set_ratio/100;
let test_set_size=$data_set_size-$training_set_size;

println ""
println "Creating symbolic links"

file_count=0;
cat $meta_file | tail -n+2  | while IFS=$'\t' read -r utt_id filename gender age native_lang length original_sample_rate content;
do
	if [[ $file_count < $training_set_size ]]; then
		ln -sf $data_set/$filename $output_dir/train/$filename || ( println "$uc_attention_mark Error: Cannot create a symbolic link to $data_set/$filename" && exit 1 ) ;
		printf "$utt_id\t$filename\t$gender\t$age\t$native_lang\t$length\t$original_sample_rate\t$content\n" >> $metadata_train;
	else
		ln -sf $data_set/$filename $output_dir/train/$filename || ( println "$uc_attention_mark Error: Cannot create a symbolic link to $data_set/$filename" && exit 1 ) ;
		printf "$utt_id\t$filename\t$gender\t$age\t$native_lang\t$length\t$original_sample_rate\t$content\n" >> $metadata_test;
	fi
	let file_count+=1;
done

println ""
println "Size of data set: $data_set_size";
println "Size of training set: $training_set_size";
println "Size of test set: $test_set_size";

println ""
println "### DONE ###"
println "Total Elapsed: $((($SECONDS - start) / 3600))hrs $(((($SECONDS - start) / 60) % 60))min $((($SECONDS - start) % 60))sec";