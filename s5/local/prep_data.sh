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
# path() { eval ${$@/text//\/\//\/}; }

# Spinner from http://fitnr.com/showing-a-bash-spinner.html
spinner()
{
    local pid=$1
    local delay=0.75
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

println "Running: $0";
SECONDS=0;

sample_rate=16000;
samromur=$(readlink -f $1);
info_file=$2;
output_dir=$3;
train_dir="$3/train/";
train_dir=${train_dir//\/\//\/};
test_dir="$3/test/";
test_dir=${test_dir//\/\//\/};
text_file=path "$3/text";
text_file=${text_file//\/\//\/};
wav_scp_file="$3/wav.scp";
wav_scp_file=${wav_scp_file//\/\//\/};
utt2spk_file="$3/utt2spk";
utt2spk_file=${utt2spk_file//\/\//\/};
spk2utt_file="$3/spk2utt";
spk2utt_file=${spk2utt_file//\/\//\/};
spk2gender_file="$3/spk2gender";
spk2gender_file=${spk2gender_file//\/\//\/};

# Checking input
println "Checking Input:";

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
println "Prepearing Filesystem:";

for dir in $output_dir $train_dir $test_dir; do
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

for file in $text_file $wav_scp_file $utt2spk_file $spk2utt_file $spk2gender_file  ; do
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

# Data preparation
println "Prepearing Data"

wav_cmd="sox - -c1 -esigned -r$sample_rate -twav - ";

cat $info_file | tail -n+2 | while IFS=$'\t' read -r utt_id filename gender age native_lang length original_sample_rate content
do
	# text
	# <utterance-id> <transcription>
	content_lower=$(echo $content | awk '{print tolower($0)}');
	echo "$utt_id $content_lower" >> $text_file;

	# wav.scp
	# <recording-id> <extended-filename>
	echo "$utt_id $filename" >> $wav_scp_file;

	# utt2spk
	# <utterance-id> <speaker-id>
	echo "$utt_id $utt_id" >> $utt2spk_file;

	# spk2utt
	# <speaker-id> <utterance-id>
	echo "$utt_id $utt_id" >> $spk2utt_file;

	# spk2gender
	# <speaker-id> <gender>
	if [[ $gender == "male" ]]; then
		g="m";
	elif [[ $gender == "female" ]]; then
		g="f";
	else
		g="u";
	fi
	echo "$utt_id $g" >> $spk2gender_file;
done &
spinner $!

for file in $text_file $wav_scp_file $utt2spk_file $spk2utt_file $spk2gender_file  ; do
	println "\t$uc_check_mark $file";
done

println "Validating Data Directory"
utils/validate_data_dir.sh --no-feats $output_dir || utils/fix_data_dir.sh $output_dir || ( println "$uc_attention_mark Error: Cannot execute validation" && exit 1 ) ;

println "Elapsed: $(($SECONDS / 3600))hrs $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec";
