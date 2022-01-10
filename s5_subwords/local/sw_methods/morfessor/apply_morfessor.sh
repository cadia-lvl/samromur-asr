#!/bin/bash

# Implematation of the morfessor subword segmentations
# The tool is avalible here https://github.com/Waino/morfessor-emprune
# Author David Erik Mollberg


if  [ $# -ne 3 ] && [ $# -ne 4 ]; then
  echo "Usage: morfessor.sh <text corpus> <subword unit count> <subword directory>"
  echo "e.g.: ./morfessor.sh rmh 1000 "
  exit 1;
fi

text=$1
subword_dir=$2
output=$3
kaldi_text="${4:-false}"
# Trick to set defult varibles of input

tmp=$subword_dir/tmp
mkdir -p $tmp

if [ $kaldi_text == 'true' ] || [ $kaldi_text == 'True' ]; then
  cut -d" " -f2- $text > $tmp/text
  cut -d" " -f1 $text > $tmp/ids
  text=$tmp/text
fi

echo "$0: Segmenting test corpus"
morfessor-segment $text \
                  --em-prune $subword_dir/emprune.model \
                  --output-format-separator '@@ ' \
                  -o $tmp/segment 

python3 local/sw_methods/morfessor/apply_segments_to_text.py $tmp/segment \
                                                             $text \
                                                             $tmp/text.sub

if [ $kaldi_text == 'true' ] || [ $kaldi_text == 'True' ]; then
  paste -d ' ' $tmp/ids $tmp/text.sub > $output
else
  mv $tmp/text.sub $output
fi

rm -r $tmp
