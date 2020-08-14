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

. ./utils.sh

println "Running: $BASH_SOURCE";

# Checking input
println "";
println "Checking Input:";

## Check number of input arguments
if [[ $# != 2 ]]; then
	println "Usage: $BASH_SOURCE <path-to-training-and-test-datasets> <iceandic-pronunciation-dict>"
	exit 1;
else
	println "\t$uc_check_mark Number of arguments"
fi

## Check input argument types
# TODO: Check if third argument is a file directory even though it hasnt been created
if [[ ! -d $1 || ! -f $2 ]]; then
	println "$uc_attention_mark Error: Invalid argument type.";
	println "Usage: $0 <path-to-training-and-test-datasets> <iceandic-pronunciation-dict>";
	println "\t<path-to-training-and-test-datasets> : File directory";
	println "\t<iceandic-pronunciation-dict> : File";	
	exit 1;
else
	println "\t$uc_check_mark Argument types"
fi

mfcc_use_energy=false
mfcc_sample_frequency=16000
sample_rate=16000;
dataset_dir=$(readlink -f $1);
train_data_dir=$dataset_dir/train;
train_data_info_file=$dataset_dir/metadata_train.tsv;
test_data_dir=$dataset_dir/test;
test_data_info_file=$dataset_dir/metadata_test.tsv;

iceandic_pronunciation_dict=$2;
# info_file=$2;

conf_dir="./conf";
exp_dir="./exp";
data_dir="./data";
data_train_dir="$data_dir/train";
data_test_dir="$data_dir/test";
data_local_dir="$data_dir/local";
data_local_lang_dir="$data_dir/local/lang";
data_local_dict_dir="$data_dir/local/dict";

mfcc_conf_file="$conf_dir/mfcc.conf"

metadata_train="";
train_text_file="$data_train_dir/text";
train_words_file="$data_train_dir/words.txt"
train_wav_scp_file="$data_train_dir/wav.scp";
train_utt2spk_file="$data_train_dir/utt2spk";
train_spk2utt_file="$data_train_dir/spk2utt";
train_spk2gender_file="$data_train_dir/spk2gender";

test_text_file="$data_test_dir/text";
test_words_file="$data_test_dir/words.txt"
test_wav_scp_file="$data_test_dir/wav.scp";
test_utt2spk_file="$data_test_dir/utt2spk";
test_spk2utt_file="$data_test_dir/spk2utt";
test_spk2gender_file="$data_test_dir/spk2gender";

corpus_file="$data_local_dict_dir/corpus.txt"

lexicon_file="$data_local_lang_dir/lexicon.txt";
nonsilence_phones_file="$data_local_lang_dir/nonsilence_phones.txt";
optional_silence_file="$data_local_lang_dir/optional_silence.txt";
silence_phones_file="$data_local_lang_dir/silence_phones.txt";

wav_cmd="sox - -c1 -esigned -r$sample_rate -twav - ";

# Preparing configuration files
println "";
println "Preparing configuration files"

# MFCC config file
echo "--use-energy="$mfcc_use_energy >> $mfcc_conf_file;
echo "--sample-frequency="$mfcc_sample_frequency >> $mfcc_conf_file;
println "\t$uc_check_mark $mfcc_conf_file";

# Preparing accoustic data for training set
println "";
println "Preparing accoustic data for the training set"

cat $train_data_info_file | tail -n+2 | while IFS=$'\t' read -r utt_id filename gender age native_lang length original_sample_rate content;
do
	# text
	# <utterance-id> <transcription>
	content_lower=$(echo $content | tr -d '[:punct:]' | awk '{print tolower($0)}');
	echo "$utt_id $content_lower" >> $train_text_file;

	# wav.scp
	# <recording-id> <extended-filename>
	echo "$utt_id $wav_cmd < $train_data_dir/$filename | " >> $train_wav_scp_file;

	# utt2spk
	# <utterance-id> <speaker-id>
	echo "$utt_id $utt_id" >> $train_utt2spk_file;

	# spk2utt
	# <speaker-id> <utterance-id>
	echo "$utt_id $utt_id" >> $train_spk2utt_file;

	# spk2gender
	# <speaker-id> <gender>
	if [[ $gender == "male" ]]; then
		g="m";
	elif [[ $gender == "female" ]]; then
		g="f";
	else
		# I tried using u, but then i get Error: Mal-formed spk2gender file
		g="f";
	fi
	echo "$utt_id $g" >> $train_spk2gender_file;
done &
spinner $!;

for file in $train_text_file $train_wav_scp_file $train_utt2spk_file $train_spk2utt_file $train_spk2gender_file  ; do
	println "\t$uc_check_mark $file";
done

# Creating dictionary
cut -d ' ' -f 2 $train_text_file | sed 's/ /\n/g' | sort -u | awk NF >> $train_words_file || exit 1;
println "\t$uc_check_mark $train_words_file";


# Create files for data/local/lang
println "";
println "Preparing language data for the training set"

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


# Preparing accoustic data for test set
println "";
println "Preparing accoustic data for the test set";
cat $test_data_info_file | tail -n+2 | while IFS=$'\t' read -r utt_id filename gender age native_lang length original_sample_rate content;
do
	# text
	# <utterance-id> <transcription>
	content_lower=$(echo $content | tr -d '[:punct:]' | awk '{print tolower($0)}');
	echo "$utt_id $content_lower" >> $test_text_file;

	# wav.scp
	# <recording-id> <extended-filename>
	echo "$utt_id $wav_cmd < $test_data_dir/$filename | " >> $test_wav_scp_file;

	# utt2spk
	# <utterance-id> <speaker-id>
	echo "$utt_id $utt_id" >> $test_utt2spk_file;

	# spk2utt
	# <speaker-id> <utterance-id>
	echo "$utt_id $utt_id" >> $test_spk2utt_file;

	# spk2gender
	# <speaker-id> <gender>
	if [[ $gender == "male" ]]; then
		g="m";
	elif [[ $gender == "female" ]]; then
		g="f";
	else
		# I tried using u, but then i get Error: Mal-formed spk2gender file
		g="f";
	fi
	echo "$utt_id $g" >> $test_spk2gender_file;
done &
spinner $!;

for file in $test_text_file $test_wav_scp_file $test_utt2spk_file $test_spk2utt_file $test_spk2gender_file  ; do
	println "\t$uc_check_mark $file";
done


println "";
println "Validating Data Directories"
println "Running: utils/validate_data_dir.sh";
println "";
utils/validate_data_dir.sh --no-feats $data_train_dir || utils/fix_data_dir.sh $data_train_dir || ( println "$uc_attention_mark Error: Cannot execute validation on $data_train_dir" && exit 1 ) ;
utils/validate_data_dir.sh --no-feats $data_test_dir || utils/fix_data_dir.sh $data_test_dir || ( println "$uc_attention_mark Error: Cannot execute validation on $data_test_dir" && exit 1 ) ;
println "Finish running: utils/validate_data_dir.sh";

# Create files for data/lang
println "";
println "Running: utils/prepare_lang.sh";
println "";
# utils/prepare_lang.sh <dict-src-dir> <oov-dict-entry> <tmp-dir> <lang-dir>
utils/prepare_lang.sh data/local/lang 'OOV' data/local/ data/lang
println "Finish running: utils/prepare_lang.sh";
