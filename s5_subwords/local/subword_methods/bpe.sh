#!/bin/bash 
#
#
# 2020 David Erik Mollberg 
#

lang=$1
text_corpus=$2 
num_merges=$3
stage=2

echo "$0: Getting PBE pairs from $text_corpus"
python3 utils/lang/bpe/learn_bpe.py -i $text_corpus -s $num_merges > data/$lang/all/pair_codes

echo "$0: Applying PBE"

python3 utils/lang/bpe/apply_bpe.py -i data/$lang/all/tokens \
                                    --codes data/$lang/all/pair_codes \
                                    | sed 's/ /\n/g' | sort -u > data/$lang/all/subwords

#ATh prófum þetta í stað fyrir næsta fall ef ekkert annað finnst
#sed 's/./& /g' data/all/subwords | sed 's/@ @ //g' | sed 's/*/V/g' | paste -d ' ' data/all/subwords - > data/all/subword_lexicon

python3 local/prepare_lexicon.py --i data/$lang/all/subwords \
                                --o data/$lang/all/subword_lexicon \
                                --is_subword True

#Bætti við all, ætti ekki að laga neit held ég.
for x in all training test; do
    utils/subword/prepare_subword_text.sh data/$lang/${x}/text \
                                        data/$lang/all/pair_codes \
                                        data/$lang/${x}/text
done

echo "$0: Preparing lexicon and lang" 
local/prepare_dict_subword.sh data/$lang/all/subword_lexicon \
                              data/$lang/training \
                              data/$lang/local/dict

utils/subword/prepare_lang_subword.sh data/$lang/local/dict \
                                    "<UNK>"\
                                    data/$lang/local/lang \
                                    data/$lang/lang
