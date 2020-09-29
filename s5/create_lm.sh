#!/bin/bash
#
# Prepares lexicon data for language modeling, creates a language model and converts to G.fst
#

corpus=$@
lm_vocab=data/local/dict
lang_dir=data/lang

# First we wil create the language model vocabulary. All the words in the corpus need to be in data/lang/words.txt 
# which is created from the lexicon
#tr ' ' '\n' < $corpus | tr -d '-' | tr -d '0-9'| sort -u > $lm_vocab/lm_vocab.txt

# create a language model and convert to fst (be sure to adjust mitlm-path in local/make_ngram.sh!)
# Get the MIT Language Modeling Toolkit here https://github.com/mitlm/mitlm
# documentation https://reposcope.com/man/en/1/estimate-ngram
# Defualt smoothing parameter ModKN
# -o, -order <int> Set the n-gram order of the estimated LM. Default: 3
#-v, -vocab <file> Fix the vocab to only words from the specified file.
# make_ngram.sh $lm_vocab/lm_vocab.txt $corpus $lmdir/trigram.arpa.gz
/home/dem/final_project/mitlm-0.4.2/estimate-ngram -o 3 -v $lm_vocab/lm_vocab.txt -t $corpus -wl $lang_dir/trigram.arpa.gz

#another way to make the lm
#utils/lang/make_kn_lm.py 3 $corpus $lmdir/trigram.arpa.gz

#Lets take the arpa file and convert it to G.fst 
arpa2G.sh $lang_dir/trigram.arpa.gz $lang_dir $lang_dir

exit 0