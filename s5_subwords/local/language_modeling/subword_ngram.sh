#David Erik Mollberg 2020
#Script to call other script to create create a subword language model. 
#To change the ngram-count, we need to change the prepare_lm_subword script

lang=$1
corpus=$2
ngram_count=6

local/language_modeling/prepare_lm_subword.sh $corpus \
                            data/$lang/local/dict/lexicon.txt \
                            data/$lang/local/lm \
                            $ngram_count \
                            data/$lang/test/text

utils/format_lm.sh  data/$lang/lang \
                    data/$lang/local/lm/lm.gz \
                    data/$lang/local/dict/lexicon.txt \
                    data/$lang/test

