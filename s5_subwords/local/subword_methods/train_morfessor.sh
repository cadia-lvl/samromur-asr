#!/bin/bash
#Implematation of the morfessor subword segmentations
#The tool is avalible here https://github.com/Waino/morfessor-emprune
#Author David Erik Mollberg

#if [ $# -ne 3 ]; then
#	error "Usage: $0 <traning-corpus> <model-path>"
#fi

corpus=$1
dir=$2
testdata=$3

mkdir -p $dir
cut -d' ' -f2- $corpus | sed 's/ /\n/g' > $dir/corpus 

corpus=$dir/corpus

# Create 1M substring seed lexicon direct from a pretokenized corpus
freq_substr.py --lex-size 1000000 < $corpus > $dir/freq_substr.1M

# Perform Morfessor EM+Prune training. Autotuning with 10k lexicon size.
morfessor \
    --em-prune $dir/freq_substr.1M \
    --traindat $corpus \
    --num-morph-types 10000 \
    --save-segmentation $dir/emprune.model

# Segment data using the Viterbi algorithm
morfessor-segment \
    $testdata \
    --em-prune $dir/emprune.model \
    --output-format-separator '@@'
    --output $dir/segmented.testdata

morfessor-segment \
    test/corpus \
    --em-prune test/emprune.model \
    --output-format-separator '@@ '
    --output test/segmented.testdata
