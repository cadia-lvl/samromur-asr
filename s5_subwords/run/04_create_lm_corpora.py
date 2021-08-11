#!/usr/bin/env python3


import re
import glob
import argparse
import math
from posixpath import dirname
import sys
import os
from typing import List, Set, Dict, Tuple, Optional
from tqdm import tqdm
import random


def get_args():
    """
    Get args from stdin.
    """
    parser = argparse.ArgumentParser(
        description="""Finds canditate sentences to remove from the text corpus to create and OOV setting""",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )

    parser.add_argument(
        "--candidates_dir",
        type=str,
        required=True,
        help="Path to the folder candidate_output created with 05_setup_experiment.py",
    )

    parser.add_argument(
        "--outdir",
        type=str,
        required=True,
        help="Path to store the corpora",
    )
    parser.add_argument(
        "--text_corpus",
        type=str,
        required=True,
        help="Path to the text corpus used to train the language models",
    )
    print(" ".join(sys.argv))

    return parser.parse_args()


def _get_file_length(file: str) -> int:
    """
    Returns length of file
    """
    count: int = 0
    with open(file) as f_in:
        for _ in f_in:
            count += 1
    return count


def _count_freq(in_file: str, contains_id=False) -> List:
    """
    Reads a standard text file with one sentence per line or a kaldi file that has the format id-sentence
    and counts the number of occrences of each word and returns a list of all words sorted by frequncey.
    """
    freq: Dict = {}
    file_length = _get_file_length(in_file)

    with open(in_file) as f_in:
        for sentence in tqdm(f_in, total=file_length):
            sentence = sentence.rstrip()
            if contains_id:
                sentence = sentence.split(" ")[1:]
            else:
                sentence = sentence.split(" ")
            for word in sentence:
                if word in freq:
                    freq[word] = freq[word] + 1
                else:
                    freq[word] = 1

    return sorted(
        [[x[0], x[1]] for x in freq.items()], key=lambda x: x[1], reverse=True
    )


def _check_if_file_exists(in_file) -> None:
    """
    Check if file exists and ask if user wants to overwrite
    """
    if os.path.exists(in_file):
        inp = input(f"Overwrite {in_file}? [y/n]\n")
        if inp not in ["y", "yes", "Y"]:
            return False
        else:
            return True


def _read_freq_file_as_list(path: str) -> List:
    """
    Reads the word frequncy file and returns a list with word-frequncy on each line
    """

    freq_list: list = []
    with open(path) as f_in:
        for line in f_in:
            line = line.rstrip()
            word, freq = line.split(" ")
            freq_list.append([word, freq])
    return freq_list


def _get_sum_of_words_from_freq(word_freq, index=1):
    """
    Returns the number of words in a set given a frequncy file
    """
    if word_freq:
        return sum([int(w[index]) for w in word_freq])
    else:
        return 0


def find_groups(root_dir: str) -> dict:
    """
    Finds the groups that should be located in root_dir
    """
    paths = {}
    for root, _dirs, files in os.walk(root_dir):
        name = os.path.split(root)[1]
        if name:
            group_num = os.path.split(root)[1].split("_")[1]
            oov_rate = os.path.split(root)[1].split("_")[2]
            paths[group_num] = {
                "oov_rate": oov_rate,
                "sets": [os.path.join(root, x) for x in files],
            }
    return paths


def _get_file_size(file) -> float:
    """
    Returns an float with the size of the file
    """
    return round(os.path.getsize(file) / (1024 * 1024 * 1024), 2)


def get_user_input(paths: dict, text_corpus_path) -> dict:
    """
    Let's ask the user if he wants create all the corpora or just a specific group.
    """
    oovs = [paths[i]["oov_rate"] for i in sorted(paths.keys())]
    num_sets = 0
    for val in paths.values():
        for _ in val["sets"]:
            num_sets += 1

    print(f"Found {len(paths)} groups with oov rate of: {', '.join(oovs)}")

    text_file_size = _get_file_size(text_corpus_path)
    print(f"The text file is {text_file_size}gb")
    print("Do you want on create the LM corpora for all groups or a specifc group?")

    s = f"[all] - create all the LM est. size {num_sets*text_file_size}gb\n"
    for i in sorted(paths.keys()):
        s += f"[{i}] group [{i}] with oov rate of {paths[i]['oov_rate']} est. size {(num_sets/len(oovs))*text_file_size}gb\n"
    while True:
        inp = input(s)
        if inp.lower() == "all":
            return paths
        elif inp in [i for i in paths.keys()]:
            return {inp: paths[inp]}
        else:
            print(
                f"'{inp}' is not a valid input choose a group to create or all of them"
            )


def create_text_corpora(paths, text_corpus, outdir) -> None:
    """
    Takes in the dict with paths to the oov word sets and the text corpus.
    Writes num_sets many new text files excluding the desired ovv words.
    """
    text_corpus_length = _get_file_length(text_corpus)

    for i in sorted(paths.keys()):
        oov_sets = {}
        all_oovs_in_set = set()
        set_num = 0
        out_dir = os.path.join(outdir, f"group_{i}_{paths[i]['oov_rate']}")
        if not os.path.exists(out_dir):
            os.makedirs(out_dir)

        for s in paths[i]["sets"]:
            new_text_corpus_path = os.path.join(out_dir, str(set_num))
            oovs = set([x.rstrip() for x in f_in])
            oov_sets[set_num] = {
                "oovs": oovs,
                "stream": open(new_text_corpus_path, "a"),
            }
            all_oovs_in_set.union(oovs)
            set_num += 1

        for s in paths[i]["sets"]:

        # with open(text_corpus) as f_in:


def main():
    args = get_args()
    paths = find_groups(args.candidates_dir)
    # paths = get_user_input(paths, args.text_corpus)
    create_text_corpora(paths, args.text_corpus, args.outdir)


if __name__ == "__main__":
    """

    e.g.
    ./run/04_create_lm_corpora.py --candidates_dir /scratch/derik/subword_journal/isl/candidate_output/ \
        --out /scratch/derik/subword_journal/isl/corpora \
        --text_corpus /mnt/scratch/derik/subword_journal/isl/text_corpora/rmh_2020-11-23+sm+malromur+althingi_sorted_cleaned_1m
    """
    main()
