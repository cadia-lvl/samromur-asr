#!/usr/bin/env python3

# Author: David Erik Mollberg, Inga Run Helgadottir (Reykjavik University)
# Description:
# This script will output the files text, wav.scp, utt2spk and spk2utt
# to data/train, data/eval data/test with test/train/eval splits defined in the metadatafile.

import subprocess
import argparse
from pathlib import Path
import pandas as pd


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="""This script will output the files text, wav.scp, utt2spk and spk2utt\n
        to data/train, data/eval and data/test, with test/train/eval splits defined in the metadatafile.\n
        Usage: python3 samromur_prep_data.py <path-to-samromur-audio> <metadata-file> <output-dir>\n
            E.g. python3 samromur_prep_data.py /data/corpora/samromur/audio/ /data/corpora/samromur/metadata.tsv data\n
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


def append_to_file(df, audio_dir: str, text, wavscp, utt2spk):
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


def clean_dir(datadir):
    subprocess.call(
        f"utils/utt2spk_to_spk2utt.pl < {datadir}/utt2spk > {datadir}/spk2utt",
        shell=True,
    )
    subprocess.call(
        f"utils/validate_data_dir.sh --no-feats {datadir} || utils/fix_data_dir.sh {datadir}",
        shell=True,
    )


def main():

    args = parse_arguments()

    audio_dir = args.audio_dir
    metadata = args.meta_file
    outdir = args.output_dir
    Path(outdir).mkdir(parents=True, exist_ok=True)

    df = pd.read_csv(metadata, sep="\t", index_col="id")

    for data_file in ["train", "dev", "eval"]:
        datadir = Path(outdir).joinpath(data_file)
        Path(datadir).mkdir(parents=True, exist_ok=True)

        print(f"\nCreating files in {datadir}")

        with open(f"{datadir}/text", "w") as text, open(
            f"{datadir}/wav.scp", "w"
        ) as wav, open(f"{datadir}/utt2spk", "w") as utt2spk:

            if data_file == "train":
                # Create new dataframes with only lines containing the current status
                df_part = df[df["status"].str.contains("train")]
                append_to_file(df_part, audio_dir, text, wav, utt2spk)

            if data_file == "dev":
                df_part = df[df["status"].str.contains("dev")]
                append_to_file(df_part, audio_dir, text, wav, utt2spk)

            if data_file == "eval":
                df_part = df[df["status"].str.contains("eval")]
                append_to_file(df_part, audio_dir, text, wav, utt2spk)

        clean_dir(datadir)


if __name__ == "__main__":
    main()
