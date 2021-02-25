#!/usr/bin/env bash

# Copyright 2012  Vassil Panayotov
#           2017  Ewald Enzinger
#           2019  Dongji Gao
#           2020  David Erik Mollberg
# Apache 2.0

. ./path.sh || exit 1

echo "=== Building a language model ..."

if [ $# -ne 5 ]; then
	echo "Usage: $0 <training-corpus> <path-to-lexicon> <output-dir> <n-gram-count> <lang>"
fi

training_corpus=$1
test=$2
lexicon=$3
dir=$4

# Language model order
order=$5

. utils/parse_options.sh

# Prepare a LM training corpus from the transcripts
mkdir -p $dir

loc=`which ngram-count`;
if [ -z $loc ]; then
  if uname -a | grep 64 >/dev/null; then # some kind of 64 bit...
    sdir=$KALDI_ROOT/tools/srilm/bin/i686-m64 
  else
    sdir=$KALDI_ROOT/tools/srilm/bin/i686
  fi
  if [ -f $sdir/ngram-count ]; then
    echo Using SRILM tools from $sdir
    export PATH=$PATH:$sdir
  else
    echo You appear to not have SRILM tools installed, either on your path,
    echo or installed in $sdir.  See tools/install_srilm.sh for installation
    echo instructions.
    exit 1
  fi
fi

cat $test | cut -d ' ' -f2- > $dir/dev.txt
cut -d' ' -f1 $lexicon > $dir/wordlist

ngram-count -text $training_corpus -order $order -vocab $dir/wordlist \
  -unk -map-unk "<UNK>" -wbdiscount1 -kndiscount2 -kndiscount3 -kndiscount4 -kndiscount5 -kndiscount6 -interpolate -lm $dir/lm.gz

#For perplexity calculations of the test set. w
ngram -order $order -lm $dir/lm.gz -ppl $dir/dev.txt
echo "*** Finished building the LM model!"

