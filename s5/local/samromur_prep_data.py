#!/usr/bin/env python3

# Author: David Erik Mollberg, Inga Run Helgadottir (Reykjavik University)
# Description:
# This script will output the files text, wav.scp, utt2spk, spk2utt and spk2gender
# to data/all, data/train data/test with test/train/eval splits defined in the metadatafile.
# The script also makes a tokens file which which contains the word types in the corpus.

import os
import subprocess
import argparse
from pathlib import Path
import pandas as pd


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="""This script will output the files text, wav.scp, utt2spk, spk2utt and spk2gender\n
        to data/all, data/train data/test with test/train/eval splits defined in the metadatafile.\n
        The script also makes a tokens file which which contains the word types in the corpus.\n
        Usage: python3 local/samromur_prep_data.py <path-to-samromur-audio> <info-file-training>\n
            E.g. python3 samromur_prep_data.py /data/corpora/samromur/audio/ metadata.tsv\n
        """
    )
    parser.add_argument(
        "audio_dir", type=dir_path, help="The Samromur audio file",
    )
    parser.add_argument(
        "meta_file", type=file_path, help="The Samromur metadata file",
    )
    parser.add_argument(
        "output_dir", type=str, help="Where to place the created files",
    )
    return parser.parse_args()


def file_path(path: str):
    if Path(path).is_file():
        return path
    else:
        raise argparse.ArgumentTypeError(f"readable_file:{path} is not a valid file")


def dir_path(path: str):
    if Path(path).is_dir():
        return path
    else:
        raise argparse.ArgumentTypeError(f"Directory:{path} is not a valid directory")


def append_to_file(df, audio_dir: str, text, wavscp, utt2spk, spk2gender):
    """
    Append relevant data to the files
    """
    for i in df.index:
        utt_id = f"{df.at[i, 'speaker_id']}-{i}"
        text.write(f"{utt_id} {df.at[i, 'sentence_norm']}\n")
        wavscp.write(
            f"{utt_id} sox - -c1 -esigned -r {df.at[i, 'sample_rate']} -twav - < {Path(audio_dir).joinpath(df.at[i, 'filename'])} |\n"
        )
        utt2spk.write(f"{utt_id} {df.at[i, 'speaker_id']}\n")

        # This line will cause in error in versions of Samrómur where the speaker is unknown
        spk2gender.write(f"{df.at[i, 'speaker_id']} {df.at[i, 'sex'][0]}\n")


def clean_dir(datadir):
    subprocess.call(
        f"utils/utt2spk_to_spk2utt.pl < {datadir}/utt2spk > {datadir}/spk2utt",
        shell=True,
    )
    subprocess.call(
        f"utils/validate_data_dir.sh --no-feats {datadir} || utils/fix_data_dir.sh {datadir}",
        shell=True,
    )
    # print('Sorting utt2spk and spk2utt')
    # subprocess.call(f"sort -k1,1 -o {datadir}/utt2spk {datadir}/utt2spk", shell=True)
    # subprocess.call(f"sort -k1,1 -o {datadir}/spk2utt {datadir}/spk2utt", shell=True)


def main():

    args = parse_arguments()

    audio_dir = args.audio_dir
    metadata = args.meta_file
    outdir = args.output_dir
    Path(outdir).mkdir(parents=True, exist_ok=True)

    df = pd.read_csv(metadata, sep="\t", index_col="id")

    for data_file in ["train", "test", "eval"]:
        datadir = Path(outdir).joinpath(data_file)
        Path(datadir).mkdir(parents=True, exist_ok=True)

        print(f"\nCreating files in {datadir}")

        with open(f"{datadir}/text", "w") as text, open(
            f"{datadir}/wav.scp", "w"
        ) as wav, open(f"{datadir}/utt2spk", "w") as utt2spk, open(
            f"{datadir}/spk2gender", "w"
        ) as spk2gender:

            if data_file == "train":
                # Create new dataframes with only lines containing the current status
                df_part = df[df["status"].str.contains("training")]
                append_to_file(df_part, audio_dir, text, wav, utt2spk, spk2gender)

            if data_file == "test":
                df_part = df[df["status"].str.contains("test")]
                append_to_file(df_part, audio_dir, text, wav, utt2spk, spk2gender)

            if data_file == "eval":
                df_part = df[df["status"].str.contains("eval")]
                append_to_file(df_part, audio_dir, text, wav, utt2spk, spk2gender)
            # if data_file == "all":
            #    with open(f"{datadir}/text", "w") as text, open(f"{datadir}/wav", "w") as wav, open(f"{datadir}/utt2spk") as utt2spk, open(f"{datadir}/spk2gender") as spk2gender:
            #        append_to_file(df_part, audio_dir, text, wav, utt2spk, spk2gender)

        clean_dir(datadir)


if __name__ == "__main__":
    main()
