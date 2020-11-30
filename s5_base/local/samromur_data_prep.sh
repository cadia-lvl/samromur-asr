#!/usr/bin/env bash
# Copyright 2020 Reykjavik University (Judy Fong - judyfong@ru.is)
# Apache 2.0.
#
# This script prepares the samromur dataset for kaldi for training, test, or
# eval datasets. The new directory have utt2spk,spk2utt,text, wav.scp

if [ $# -ne 3 ]; then
  echo "Usage: $0 <samromur-speech> <sammromur-type> <out-data-dir>"
  echo "e.g.: $0 /mnt/data/samromur training data/"
  exit 1;
fi

set -e

data_type=$2
data_dir=$3
audio_src_dir=$1/audio/
metadata=$1/metadata.tsv

tmp_dir=$data_dir/samromur_${data_type}/.tmp/
mkdir -p $tmp_dir

cat $metadata | sed '1d' > $tmp_dir/metadata.tsv
cat $tmp_dir/metadata.tsv | awk -F'\t' '{print($1"\t"$2"\t"$3"\t"$10"\t"$11)}' \
> $tmp_dir/usefuldata.tsv

i=1
while IFS=$'\t' read -r id name spk sentence type; do
  if [ "$type" = "$data_type" ]; then
    # create utt2spk
    echo "$spk-$id $spk" >> $data_dir/samromur_${data_type}/utt2spk
    # create normalized text file
    echo "$spk-$id $sentence" >> $data_dir/samromur_${data_type}/text
    # create wav.scp
    echo "$spk-$id sox -twav - -c1 -esigned -r16000 -G -twav - < $audio_src_dir/$name |" >> $data_dir/samromur_${data_type}/wav.scp
  fi
done < $tmp_dir/usefuldata.tsv

utils/utt2spk_to_spk2utt.pl $data_dir/samromur_${data_type}/utt2spk > $data_dir/samromur_${data_type}/spk2utt

rm -rf $tmp_dir
