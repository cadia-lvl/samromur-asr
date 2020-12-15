#!/usr/bin/env bash

set -eo pipefail

# I had troubles with calling cmd before starting lmplz because the arpa output was put into the log file.
stage=0
order=4
#small=false # pruned or not
min1cnt=6
min2cnt=3
min3cnt=0

carpa=true

. ./path.sh
. parse_options.sh || exit 1;
. ./local/utils.sh

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

if [ $# != 3 ]; then
    echo "This script creates language models"
    echo ""
    echo "Usage: local/create_LM.sh [options] <input-text-file> <lang-dir> <lexicon>"
    echo "e.g.: local/create_LM.sh data/language_model/LMtext.txt data/lang_model data/local/dict/lexicon.txt"
    echo ""
    echo "Options:"
    echo "     --order <num>        # The ngram order of the LM"
    echo "     --small <bool>       # Prune if true (default: false)"
    echo "     --pruning <string>   # How to prune, e.g. '--prune 0 0 1' (default --prune 0 3 5)"
    echo "     --carpa <bool>       # Make a constant arpa lm if true, otherwise convert arpa to fst"
    exit 1;
fi

lmtext=$1
langdir=$2
lexicon=$3
mkdir -p "$langdir"/log

[ ! -d "$langdir" ] && echo "$0: expected $langdir to exist" && exit 1;
for f in $lmtext $lexicon; do \
    [ ! -f "$f" ] && echo "$0: expected $f to exist" && exit 1;
done

affix=_${min3cnt}${min2cnt}${min1cnt}pruned
#[ $small = true ] && pruning="--prune 0 3 5" && affix=_035pruned

if [ $stage -le 1 ]; then
    
    echo "Build ARPA-format language model"
    #cut -d' ' -f1 "$langdir"/words.txt | grep -E -v "<eps>|<unk>" > "$tmp"/words.tmp
    lmplz \
    --skip_symbols \
    -o ${order} -S 70% \
    --prune $min3cnt $min2cnt $min1cnt \
    --text "$lmtext" \
    --limit_vocab_file <(cut -d' ' -f1 "$langdir"/lang_${order}g/words.txt | grep -Ev "<eps>|<unk>") \
    | gzip -c > "$langdir"/kenlm_${order}g${affix}.arpa.gz || error 1 "lmplz failed"
fi

if [ $stage -le 2 ]; then
    if [ $carpa = true ]; then
        echo "Build constant ARPA language model"
        utils/build_const_arpa_lm.sh \
        "$langdir"/kenlm_${order}g${affix}.arpa.gz \
        "$langdir" "$langdir" || error 1 "Failed creating a const. ARPA LM"
    else
        echo "Convert ARPA-format language models to FSTs."
        utils/format_lm.sh \
        "$langdir" "$langdir"/kenlm_${order}g${affix}.arpa.gz \
        "$lexicon" "$langdir" || error 1 "Failed creating G.fst"
    fi
fi

exit 0;
