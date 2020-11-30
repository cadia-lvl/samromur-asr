#!/usr/bin/env bash
# Copyright   2020 Reykjavik University (Author: Judy Fong - judyfong@ru.is)
# Apache 2.0

# Description: create the data/local/dict directory to make data/lang for samromur
# This file should be called by run.sh

textfile=$1 # training/text
data_dir=$2
dict_dir=$data_dir/local/dict
# TODO: have g2p as a parameter
g2p_model=/data/models/g2p/sequitur/althingi/g2p.mdl

tmp_dir=$data_dir/.tmp/
mkdir -p $tmp_dir
mkdir -p $dict_dir
mkdir -p $data_dir/lang

# If there already is a lexicon use it instead of creating one
if [ ! -f $dict_dir/lexicon.txt ]; then

  # TODO: check to see if sequitur is installed
  # Turn text into a list of unique words in the training set
  cat $textfile | cut -d' ' -f2- | sed 's/ /\n/g' | sort -u | sed '/^\s*$/d' > $tmp_dir/wordlist.txt

  # Create a lexicon from a g2p model and the words from training/text
  ./local/transcribe_g2p.sh $g2p_model $tmp_dir/wordlist.txt > $tmp_dir/transcribed_words.txt
  # TODO: filter out words with no phonetic transcription
  cat $tmp_dir/transcribed_words.txt | sed '/^aa\t$/d' > $tmp_dir/filtered.txt
  # Add the unknown symbol to the lexicon
  echo -e "<UNK>\tsil" > $dict_dir/lexicon.txt
  # Create lexicon
  cat $tmp_dir/filtered.txt >> $dict_dir/lexicon.txt

else
  echo "Lexicon file already exists. Using it."
fi

nonsil_phones=$dict_dir/nonsilence_phones.txt
extra_questions=$dict_dir/extra_questions.txt
silence_phones=$dict_dir/silence_phones.txt
optional_silence=$dict_dir/optional_silence.txt

# TODO: create nonsilence_phones.txt
# note: LC_ALL=C needed for sort uniq because of uniqs weird behaviour with these unicode chars
cut -f2- $tmp_dir/filtered.txt \
    | tr ' ' '\n' | LC_ALL=C sort -u > $nonsil_phones

# TODO: add content to extra_questions.txt
touch $extra_questions

# create optional_silence.txt
echo 'sil' > $optional_silence

# create silence_phones.txt
echo 'sil \n oov' > $silence_phones

echo "$(wc -l <$silence_phones) silence phones saved to: $silence_phones"
echo "$(wc -l <$optional_silence) optional silence saved to: $optional_silence"
echo "$(wc -l <$nonsil_phones) non silence phones saved to: $nonsil_phones"

# create the lang directory
utils/prepare_lang.sh $dict_dir '<UNK>' $data_dir/local/lang $data_dir/lang

# Validate lang directory
utils/validate_lang.pl $data_dir/lang || error "Invalid lang dir"

rm -rf $tmp_dir
