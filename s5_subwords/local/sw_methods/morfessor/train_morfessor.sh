#!/bin/bash
#Implematation of the morfessor subword segmentations
#The tool is avalible here https://github.com/Waino/morfessor-emprune
#Author David Erik Mollberg


if [ $# -ne 3 ]; then
  echo "Usage: morfessor.sh <text corpus> <subword unit count> <subword directory>"
  echo "e.g.: ./morfessor.sh rmh 1000 "
  exit 1;
fi

text_corpus=$1
vocab_size=$2
subword_dir=$3

# We need a tokenized file for the next step
echo "$0: Tokenizing file"
cut -d' ' -f2- $text_corpus | sed 's/ /\n/g' > $subword_dir/tokens

# Creating substring seed lexicon direct from a pretokenized corpus
echo "$0: Creating substring seed lexicon"
freq_substr.py --lex-size 1000000 < $subword_dir/tokens > $subword_dir/freq_substr

# Perform Morfessor EM+Prune training.
echo "$0: Performing Morfessor EM+Prune training"
morfessor --em-prune $subword_dir/freq_substr \
          --traindata $text_corpus \
          --num-morph-types $vocab_size \
          --save-segmentation $subword_dir/emprune.model