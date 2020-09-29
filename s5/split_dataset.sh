#!/bin/bash -eu
#
# Author: Egill Anton Hlöðversson
# 
# Splits a dataset into training and test set
# Made for Samrómur-ASR dataset
# Example of usage
# ./split_dataset.sh ~/samromur/audio/ ~/samromur1000/metadata.tsv 80 ~/samromur

. ./utils.sh

println "Running: $BASH_SOURCE";
println ""
println "Checking Input:";

# Check number of input arguments
if [[ $# != 4 ]]; then
	println "Usage: $0 <path-to-samromur-audio> <path-to-samromur-meta-file> <training-set-split-ratio> <output-dir> ";
	exit 1;
else
	println "\t$uc_check_mark Number of arguments"
fi

# Checking argument types
if [[ ! -d $1 || ! -f $2 || ! -n $3 ]]; then
	println "$uc_attention_mark Error: Invalid argument type.";
	println "Usage: $BASH_SOURCE <path-to-samromur-audio-directory> <path-to-samromur-meta-file> <training-set-split-ratio>";
	println "\t<path-to-samromur-audio> : File directory";
	println "\t<info-file-training> : File";
	println "\t<training-set-split-ratio> : Integer";
	println "\t<output-dir> : File directory";
	exit 1;
else
	println "\t$uc_check_mark Argument types";
fi

# Get input
data_set=$(readlink -f $1);
meta_file=$2;
traing_set_ratio=$3;
output_dir=$4;

metadata_train=$output_dir/metadata_train.tsv;
metadata_test=$output_dir/metadata_test.tsv;

# Preparing filesystem
println ""
println "Preparing Filesystem:";

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

# Calculate the split
data_set_size=$(ls $data_set | wc -l);
let training_set_size=$data_set_size*$traing_set_ratio/100;
let test_set_size=$data_set_size-$training_set_size;

println ""
println "Creating symbolic links"

#To do Add spinner
# Training dataset
cat $meta_file | head -n $(($training_set_size+1)) | tail -n+2  | while IFS=$'\t' read -r utt_id filename gender age native_lang length original_sample_rate content;
do
	ln -sf $data_set/$filename $output_dir/train/$filename || ( println "$uc_attention_mark Error: Cannot create a symbolic link to $data_set/$filename" && exit 1 );
	printf "$utt_id\t$filename\t$gender\t$age\t$native_lang\t$length\t$original_sample_rate\t$content\n" >> $metadata_train;
done

# Test dataset
cat $meta_file | tail -n+$(($training_set_size+2))  | while IFS=$'\t' read -r utt_id filename gender age native_lang length original_sample_rate content;
do
	ln -sf $data_set/$filename $output_dir/test/$filename || ( println "$uc_attention_mark Error: Cannot create a symbolic link to $data_set/$filename" && exit 1 );
	printf "$utt_id\t$filename\t$gender\t$age\t$native_lang\t$length\t$original_sample_rate\t$content\n" >> $metadata_test;
done

println "\t$uc_add $(ls -la $output_dir/train | grep "\->" | wc -l) symbolic links created in: $output_dir/train/";
println "\t$uc_add $(ls -la $output_dir/test | grep "\->" | wc -l) symbolic links created in: $output_dir/test/";
println "\t$uc_check_mark $(wc -l $metadata_train | cut -f1 -d' ') lines added to: $metadata_train";
println "\t$uc_check_mark $(wc -l $metadata_test | cut -f1 -d' ') lines added to: $metadata_test";
