#!/bin/bash
# Copyright 2020 Reykjavik University (Judy Fong - judyfong@ru.is)
# Apache 2.0.
#
# This script prepares the samromur dataset for kaldi for training, test, or
# eval datasets. The new directory have utt2spk,spk2utt,text, wav.scp

if [ $# -ne 2 ]; then
    echo "Usage: $0 <samromur-speech> <out-data-dir>"
    echo "e.g.: $0 /data/asr/samromur/samromur_21.05 data/"
    exit 1;
fi

set -e

dataset_dir=$1
data_dir=$2
metadata=$1/metadata.tsv
tmp_dir=$data_dir/local/samromur

mkdir -p $tmp_dir

# Folder structure setup
for subset in train test dev; do
  [[ -d $data_dir/${subset}_samromur ]] && rm -r $data_dir/${subset}_samromur
  mkdir -p $data_dir/${subset}_samromur
  sed -e 1d $metadata | cut -f2,3,5,19 | grep "$subset$" > $tmp_dir/$subset.tsv

  awk -F '\t' '{print $2,$1}' $tmp_dir/$subset.tsv | sed 's/.flac//' > $data_dir/${subset}_samromur/utt2spk
  awk -F '\t' '{print $2,$3}' $tmp_dir/$subset.tsv | sed 's/.flac//' > $data_dir/${subset}_samromur/text
  awk -F '\t' -v var=$dataset_dir '{print $2,"sox -tflac - -c1 -esigned -r16000 -G -twav - <",var"/"$4"/"$1"/"$2"|"}' \
    $tmp_dir/$subset.tsv | sed 's/.flac//' > $data_dir/${subset}_samromur/wav.scp

  utils/utt2spk_to_spk2utt.pl $data_dir/${subset}_samromur/utt2spk > $data_dir/${subset}_samromur/spk2utt

done

echo "Done, Samromur dataset in $data_dir."
exit 0;
