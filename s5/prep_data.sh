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

mfcc_use_energy=false
mfcc_sample_frequency=16000

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

println "Running: $BASH_SOURCE";

# Checking input
println ""
println "Checking Input:";

## Check number of input arguments
if [[ $# != 3 ]]; then
	println "Usage: $0 <path-to-samromur-audio> <info-file-training> <iceandic-pronunciation-dict>"
	exit 1;
else
	println "\t$uc_check_mark Number of arguments"
fi

## Check input argument types
# TODO: Check if third argument is a file directory even though it hasnt been created
if [[ ! -d $1 || ! -f $2 || ! -f $3 ]]; then
	println "$uc_attention_mark Error: Invalid argument type.";
	println "Usage: $0 <path-to-samromur-audio> <info-file-training> <iceandic-pronunciation-dict>";
	println "\t<path-to-samromur-audio> : File directory";
	println "\t<info-file-training> : File";
	println "\t<iceandic-pronunciation-dict> : File";
	
	exit 1;
else
	println "\t$uc_check_mark Argument types"
fi

sample_rate=16000;
samromur=$(readlink -f $1);
info_file=$2;
iceandic_pronunciation_dict=$3

conf_dir="./conf";
exp_dir="./exp";
data_dir="./data";
train_dir="$data_dir/train";
test_dir="$data_dir/test";
local_dir="$data_dir/local";
local_lang_dir="$data_dir/local/lang";

mfcc_conf_file="$conf_dir/mfcc.conf"

text_file="$train_dir/text";
words_file="$train_dir/words.txt"
wav_scp_file="$train_dir/wav.scp";
utt2spk_file="$train_dir/utt2spk";
spk2utt_file="$train_dir/spk2utt";
spk2gender_file="$train_dir/spk2gender";

lexicon_file="$local_lang_dir/lexicon.txt";
nonsilence_phones_file="$local_lang_dir/nonsilence_phones.txt";
optional_silence_file="$local_lang_dir/optional_silence.txt";
silence_phones_file="$local_lang_dir/silence_phones.txt";


# Preparing filesystem
println ""
println "Preparing Filesystem:";

for dir in $conf_dir $exp_dir $data_dir $train_dir $test_dir $local_dir $local_lang_dir; do
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

for file in $mfcc_conf_file $text_file $words_file $wav_scp_file $utt2spk_file $spk2utt_file $spk2gender_file $nonsilence_phones_file $optional_silence_file $silence_phones_file; do
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

# Create symbolic links to wjs/utils and wjs/steps
if ! [ -L "./utils" ]; then
	# If symbolic link doesn't exists
	ln -s $KALDI_ROOT/egs/wsj/s5/utils utils || ( println "$uc_attention_mark Error: Cannot create a symbolic link to $KALDI_ROOT/egs/wsj/s5/utils" && exit 1 ) ;
	println "\t$uc_add Symbolic link created: ./utils -> $KALDI_ROOT/egs/wsj/s5/utils";
else
	println "\t$uc_check_mark ./utils -> $KALDI_ROOT/egs/wsj/s5/utils"
fi

if ! [ -L "./steps" ]; then
	# If symbolic link doesn't exists
	ln -s $KALDI_ROOT/egs/wsj/s5/steps steps || ( println "$uc_attention_mark Error: Cannot create a symbolic link to $KALDI_ROOT/egs/wsj/s5/steps" && exit 1 ) ;
	println "\t$uc_add Symbolic link created: ./steps -> $KALDI_ROOT/egs/wsj/s5/steps";
else
	println "\t$uc_check_mark ./steps -> $KALDI_ROOT/egs/wsj/s5/steps"
fi


# Data preparation
println ""
println "Preparing configuration files"

# Create MFCC config file
echo "--use-energy="$mfcc_use_energy >> $mfcc_conf_file;
echo "--sample-frequency="$mfcc_sample_frequency >> $mfcc_conf_file;
println "\t$uc_check_mark $mfcc_conf_file";


println ""
println "Preparing accoustic data"

wav_cmd="sox - -c1 -esigned -r$sample_rate -twav - ";

cat $info_file | tail -n+2 | while IFS=$'\t' read -r utt_id filename gender age native_lang length original_sample_rate content;
do
	# text
	# <utterance-id> <transcription>
	content_lower=$(echo $content | tr -d '[:punct:]' | awk '{print tolower($0)}');
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
spinner $!;

for file in $text_file $wav_scp_file $utt2spk_file $spk2utt_file $spk2gender_file  ; do
	println "\t$uc_check_mark $file";
done

# Creating dictionary
cut -d ' ' -f 2 $text_file | sed 's/ /\n/g' | sort -u | awk NF >> $words_file || exit 1;
println "\t$uc_check_mark $words_file";


# Create files for data/local/lang
println ""
println "Preparing language data"


cat $iceandic_pronunciation_dict  | sort -f | uniq > $lexicon_file;

# nonsilence_phones.txt
cut -f 2 $lexicon_file | sed 's/ /\n/g' | sort -u > $nonsilence_phones_file;
println "\t$uc_check_mark $nonsilence_phones_file";

# Add OOV symbol to lexicon
(echo "SIL SIL" && cat $lexicon_file) > temp && mv temp $lexicon_file;
(echo "OOV OOV" && cat $lexicon_file) > temp && mv temp $lexicon_file;
println "\t$uc_check_mark $lexicon_file";

# silence_phones.txt
echo 'SIL' >> $silence_phones_file;
echo 'OOV' >> $silence_phones_file;
println "\t$uc_check_mark $silence_phones_file";

# optional_silence.txt
echo 'SIL' > $optional_silence_file;
println "\t$uc_check_mark $optional_silence_file";

# TODO: create extra_questions.txt ?
# A Kaldi script will generate a basic extra_questions.txt file for you, but in data/lang/phones. 
# This file “asks questions” about a phone’s contextual information by dividing the phones into two different sets. 
# An algorithm then determines whether it is at all helpful to model that particular context.
# The standard extra_questions.txt will contain the most common “questions.” 
# An example would be whether the phone is word-initial vs word-final. 
# If you do have extra questions that are not in the standard extra_questions.txt file, they would need to be added here.


println ""
println "Validating Data Directory"
println "Running: utils/validate_data_dir.sh";
println ""
utils/validate_data_dir.sh --no-feats $train_dir || utils/fix_data_dir.sh $train_dir || ( println "$uc_attention_mark Error: Cannot execute validation" && exit 1 ) ;
println "Finish running: utils/validate_data_dir.sh";

# Create files for data/lang
println ""
println "Running: utils/prepare_lang.sh";
println ""
# utils/prepare_lang.sh <dict-src-dir> <oov-dict-entry> <tmp-dir> <lang-dir>
utils/prepare_lang.sh data/local/lang 'OOV' data/local/ data/lang
println "Finish running: utils/prepare_lang.sh";