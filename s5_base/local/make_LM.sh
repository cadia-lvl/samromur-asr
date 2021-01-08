#!/bin/bash -e

set -o pipefail

stage=0
order=4
small=false # pruned or not
pruning=
carpa=true

. ./path.sh
. parse_options.sh || exit 1;
. ./local/utils.sh

if [ $# != 4 ]; then
  echo "This script creates language models"
  echo ""
  echo "Usage: local/make_LM.sh [options] <input-text-file> <lang-dir> <dict-dir> <language-model-dir>"
  echo "e.g.: local/make_LM.sh data/language_model/LMtext.txt data/lang data/local/dict/lexicon.txt models/language_model/"
  echo ""
  echo "Options:"
  echo "     --order <num>        # The ngram order of the LM"
  echo "     --small <bool>       # Prune if true (default: false)"
  echo "     --pruning <string>   # How to prune, e.g. '--prune 0 0 1' (default --prune 0 3 5)"
  echo "     --carpa <bool>       # Make a constant arpa lm if true, otherwise convert arpa to fst"
  exit 1;
fi

lmtext=$1
lang=$2
lexicon=$3
dir=$4

[ ! -d $lang ] && echo "$0: expected $lang to exist" && exit 1;
for f in $lmtext $lexicon; do \
  [ ! -f $f ] && echo "$0: expected $f to exist" && exit 1;
done 

suffix=
affix=
[ $small = true ] && suffix=small && pruning="--prune 0 3 5" && affix=_035pruned

if [ $stage -le 1 ]; then
  # Preparing the language model
  mkdir -p $dir/lang_${order}g${suffix}
  for s in L_disambig.fst L.fst oov.int oov.txt phones phones.txt \
                          topo words.txt; do
    [ ! -e $dir/lang_${order}g${suffix}/$s ] && cp -r $lang/$s $dir/lang_${order}g${suffix}/$s
  done

  echo "Build ARPA-format language model"
  lmplz \
    --skip_symbols \
    -o ${order} -S 70% $pruning \
    --text $lmtext \
    --limit_vocab_file <(cut -d' ' -f1 $dir/lang_${order}g${suffix}/words.txt | egrep -v "<eps>|<unk>") \
    | gzip -c > $dir/lang_${order}g${suffix}/kenlm_${order}g${affix}.arpa.gz || error 1 "lmplz failed"
fi

if [ $stage -le 2 ]; then
  if [ $carpa = true ]; then
    echo "Build constant ARPA language model"
    utils/build_const_arpa_lm.sh \
      $dir/lang_${order}g${suffix}/kenlm_${order}g${affix}.arpa.gz \
      $lang $dir/lang_${order}g${suffix} || error 1 "Failed creating a const. ARPA LM"
  else
    echo "Convert ARPA-format language models to FSTs."
    utils/format_lm.sh \
      $lang $dir/lang_${order}g${suffix}/kenlm_${order}g${affix}.arpa.gz \
      $lexicon $dir/lang_${order}g${suffix} || error 1 "Failed creating G.fst"
  fi
fi

exit 0;
