#!/bin/bash
# Copyright (c) 2013, Ondrej Platek, Ufal MFF UK <oplatek@ufal.mff.cuni.cz>
#               2018, Inga Run Helgadottir, Reykjavik University
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
# WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
# MERCHANTABLITY OR NON-INFRINGEMENT.
# See the Apache 2 License for the specific language governing permissions and
# limitations under the License. #

. ./path.sh
. ./local/utils.sh

if [ $# != 3 ]; then
  echo "This script creates a zerogram language model"
  echo ""
  echo "Usage: local/make_zgLM.sh <lang-dir> <dict-dir> <language-model-dir>"
  echo "e.g.: local/make_zgLM.sh lm_dir/lang data/local/dict/lexicon.txt lm_dir/lang_zg"
  echo ""
  exit 1;
fi

lang=$1; shift
lexicon=$1; shift
zglmdir=$1; shift

mkdir -p $zglmdir

function build_0gram {
  lm=$1
  echo "=== Building zerogram $lm..."
  python -c """
import math
with open('$lm', 'r+') as f:
    lines = f.readlines()
    p = math.log10(1/float(len(lines)));
    lines = ['%f\\t%s'%(p,l) for l in lines]
    f.seek(0); f.write('\\n\\\\data\\\\\\nngram  1=       %d\\n\\n\\\\1-grams:\\n' % len(lines))
    f.write(''.join(lines) + '\\\\end\\\\')
"""
}

echo "=== Building zerogram LM using $lang/words.txt..."
mkdir -p $zglmdir
for s in L_disambig.fst L.fst oov.int oov.txt phones phones.txt \
  topo words.txt; do
  [ ! -e $zglmdir/$s ] && cp -r $lang/$s $zglmdir/$s
done

cut -d' ' -f1 $lang/words.txt | egrep -v "<eps>|#0" > $zglmdir/zerogram.arpa
build_0gram $zglmdir/zerogram.arpa || error 1 "build_0gram failed"

gzip $zglmdir/zerogram.arpa

echo "Convert ARPA-format language models to FSTs."
utils/format_lm.sh \
  $lang $zglmdir/zerogram.arpa.gz \
  $lexicon $zglmdir || error 1 "Failed creating G.fst"
    
echo "*** LMs preparation finished!"

exit 0;
