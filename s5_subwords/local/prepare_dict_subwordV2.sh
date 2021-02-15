#!/usr/bin/env bash

# Copyright 2017 QCRI (author: Ahmed Ali)
#           2019 Dongji Gao
#           2020 David Erik Mollberg
# Apache 2.0
# This script prepares the subword dictionary.

if [ $# -ne 3 ]; then
    echo "Usage:  $0 <subword-tokenized-text-corpus> <subword-dir> <dst-dir>" 
    exit 1
fi

set -eo pipefail

text_corpus=$1
subword_dir=$2 
dir=$3

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh || exit 1;

mkdir -p $dir 

echo "$0: Preparing dictionary"
#cut -d" " -f2- $text_corpus | sed 's/ /\n/g' | sort -u | sed '/^$/d' > $subword_dir/subwords 
cat $text_corpus | sed 's/ /\n/g' | sort -u | sed '/^$/d' > $subword_dir/subwords 

python3 local/prepare_lexiconV2.py --i $subword_dir/subwords \
                                   --o $subword_dir/subword_lexicon

cut -d' ' -f2- $subword_dir/subword_lexicon | sed 's/SIL//g' | tr ' ' '\n' | sort -u | sed '/^$/d' > $dir/nonsilence_phones.txt || exit 1;

echo @ >> $dir/nonsilence_phones.txt # This might be unnecessary, be sure to test.
echo UNK >> $dir/nonsilence_phones.txt
echo SIL > $dir/silence_phones.txt
echo SIL > $dir/optional_silence.txt
echo -n "" > $dir/extra_questions.txt

glossaries="<UNK> <sil>"

cut -d ' ' -f1 $subword_dir/subword_lexicon > $dir/words.txt
cat $subword_dir/subword_lexicon | sort -u > $dir/lexicon.txt 


sed -i'.bak' '1i<UNK> UNK' $dir/lexicon.txt
echo '<sil> SIL' >> $dir/lexicon.txt
sed -i '/^ *$/d' $dir/lexicon.txt
echo "$0: Dictionary preparation succeeded"
