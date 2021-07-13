#!/usr/bin/env bash

# Copyright 2020 David Erik Mollberg
# Apache 2.0

# This script prepares a grapaheme based dictionary folder.

if [ $# -ne 3 ]; then
    echo "Usage:  $0 <subword-tokenized-text-corpus> <tmp> <dict-dst-dir>" 
    exit 1
fi

set -eo pipefail

text_corpus=$1
tmp=$2 
dict=$3

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh || exit 1;

mkdir -p $dict $tmp 

echo "$0: Preparing dictionary"

# This step can take some time on a large corpus. srun is used for the slurm
# workload manager. It can be removed if that is not being used
srun cat $text_corpus | sed 's/ /\n/g' | sort -u | sed '/^$/d' > $tmp/words 

echo "$0: Creating lexicon" 
local/prepare_lexicon.py < $tmp/words > $tmp/lexicon 

echo "$0: Gathering non-silence phones"
cut -d' ' -f2- $tmp/lexicon | sed 's/SIL//g'| tr ' ' '\n' | sort -u | sed '/^$/d' > $dict/nonsilence_phones.txt || exit 1;

echo SIL > $dict/silence_phones.txt
echo OOV >> $dict/silence_phones.txt
echo SIL > $dict/optional_silence.txt
echo -n "" > $dict/extra_questions.txt

cut -d ' ' -f1 $tmp/lexicon > $dict/words.txt
cat $tmp/lexicon | sort -u > $dict/lexicon.txt 

sed -i'.bak' '1i<UNK> OOV' $dict/lexicon.txt
echo '<sil> SIL' >> $dict/lexicon.txt
sed -i '/^ *$/d' $dict/lexicon.txt
echo "$0: Dictionary preparation succeeded"
