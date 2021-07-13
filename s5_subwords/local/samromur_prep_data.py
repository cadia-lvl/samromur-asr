#!/usr/bin/env python3

# Author: David Erik Mollberg, Inga Run Helgadottir (Reykjavik University)
# Description:
# This script will output the files text, wav.scp, utt2spk, spk2utt and spk2gender

import subprocess
import argparse
from pathlib import Path
import pandas as pd

def parse_arguments():
    parser = argparse.ArgumentParser(
        description="""This script will output the files text, wav.scp, utt2spk, spk2utt and spk2gender
                        to data/train, data/eval and data/test, with test/train/eval splits defined in the metadatafile.
                        Usage: python3 samromur_prep_data.py <path-to-samromur-audio> <info-file-training>
                        E.g. python3 samromur_prep_data.py -a /data/corpora/samromu_r1/ \
                                -m /data/corpora/samromu_r1/metadata.tsv \
                                -o data   """ )
    parser.add_argument("-a", "--audio_dir", type=dir_path, help="The Samrór root directory", )
    parser.add_argument("-m", "--meta_file", type=file_path, help="The Samrómur metadata file. ")
    parser.add_argument("-o", "--output_dir", type=str, default='', help="Where to place the created files", )
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


def append_to_file(df:pd.DataFrame, audio_dir:str, text, wavscp, utt2spk, spk2gender):
    """
    Append relevant data to the files
    """
    # NOTE! If we use something else that a counter in the ID, e.g. the recording ID,
    # we could skip the loop and just used vectorized operations
    for i in df.index:
        utt_id = df.at[i, 'filename'].replace('.flac', '')
        text.write(f"{utt_id} {df.at[i, 'sentence_norm']}\n")
        wavscp.write(f"{utt_id} sox - -c1 -esigned -r {df.at[i, 'sample_rate']} -twav - < {Path(audio_dir).joinpath(df.at[i, 'status'], df.at[i, 'speaker_id'], df.at[i, 'filename'])} |\n")
        utt2spk.write(f"{utt_id} {df.at[i, 'speaker_id']}\n")

        if df.at[i, 'gender'] == 'male': g = "m"
        elif df.at[i, 'gender'] == 'female': g = "f"
        else: g = "f" 
        spk2gender.write(f"{df.at[i, 'speaker_id']} {g}\n")


def clean_dir(datadir):
    subprocess.call(f"utils/utt2spk_to_spk2utt.pl < {datadir}/utt2spk > {datadir}/spk2utt",
        shell=True)
    subprocess.call(f"utils/validate_data_dir.sh --no-feats {datadir} || utils/fix_data_dir.sh {datadir}",
        shell=True)


def main():

    args = parse_arguments()

    audio_dir = args.audio_dir
    metadata = args.meta_file
    outdir = args.output_dir
    Path(outdir).mkdir(parents=True, exist_ok=True)

    df = pd.read_csv(metadata, sep="\t", dtype="str")
    df = df.sort_values(by=['speaker_id', 'id'], ascending=True)
    df.set_index('id', inplace=True)

    for data_file in ["train", "dev", "test"]:
        datadir = Path(outdir).joinpath(data_file)
        Path(datadir).mkdir(parents=True, exist_ok=True)

        print(f"\nCreating files in {datadir}")

        with open(f"{datadir}/text", "w") as text, \
             open(f"{datadir}/wav.scp", "w" ) as wav, \
             open(f"{datadir}/utt2spk", "w") as utt2spk, \
             open(f"{datadir}/spk2gender", "w") as spk2gender:

            df_subset = df[df["status"] == data_file]
            append_to_file(df_subset, audio_dir, text, wav, utt2spk, spk2gender)

        clean_dir(datadir)


if __name__ == "__main__":
    main()
