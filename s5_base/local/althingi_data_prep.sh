#!/bin/bash
# Copyright 2020 Reykjavik University (Judy Fong - judyfong@ru.is)
# Apache 2.0.
#
# This script prepares the althingi dataset for kaldi for training, test, or
# eval datasets. The new directory have utt2spk,spk2utt,text, wav.scp
# use utils/data/combine_data.sh to join it all together

if [ $# -ne 2 ]; then
    echo "Usage: $0 <althingi-speech> <out-data-dir>"
    echo "e.g.: $0 /data/asr/althingi/LDC2021S01/data data/"
    exit 1;
fi

set -e

data_dir=$1
data_dir=$2
audio_dir=$1/audio/
meta_dir=$1/malfong


for i in train dev eval; do

  # Remove if exists
  [[ -d $data_dir/${i}_althingi ]] && rm -r $data_dir/${i}_althingi

  # Copy existing split
  cp -r $meta_dir/$i $data_dir/${i}_althingi || exit 1;

  # Create wav.scp
  awk -v audio="$audio_dir" '{print $1, "sox -tmp3 - -c1 -esigned -r16000 -G -twav - < ",audio$2,"|"}' \
    $data_dir/${i}_althingi/reco2audio > $data_dir/${i}_althingi/wav.scp || exit 1;

done

  mv data/eval_althingi data/test_althingi


echo "Done: Althingi dataset in $data_dir."
exit 0;

