#!/bin/bash
#Implematation of the morfessor subword segmentations
#The tool is avalible here https://github.com/Waino/morfessor-emprune
#Author David Erik Mollberg


if [ $# -ne 4 ]; then
  echo "Usage: morfessor.sh <text corpus> <subword unit count> <subword directory>"
  echo "e.g.: ./morfessor.sh rmh 1000 "
  exit 1;
fi

text=$1
subword_dir=$
output_dir=$3
kaldi_text=$4


if [ $kaldi_text == 'true' ] || [ $kaldi_text == 'True' ]; then
  mkdir -p $output_dir/temp
  
  #cut -d" " -f1 $text > $output_dir/temp/ids
  cut -d" " -f2- $text > $output_dir/temp/text
  text=$output_dir/temp/text
fi

echo "$0: Segmenting test corpus"
morfessor-segment $text \
                  --em-prune $subword_dir/emprune.model \
                  --output-format-separator '@@ ' \
                  -o $output_dir/temp/segment 


python3 apply_segments_to_text.py $output_dir/temp/segment $text $output_dir/text.sub


if [ $kaldi_text == 'true' ] || [ $kaldi_text == 'True' ]; then
 
  cut -d" " -f1 $text | paste -d ' ' - ${word_text}.sub > $subword_text
  text=$output_dir/temp/text
fi