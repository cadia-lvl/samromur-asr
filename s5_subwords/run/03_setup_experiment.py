#!/usr/bin/env python3


import argparse
import math
import sys
import os
from typing import List, Dict, Tuple
from tqdm import tqdm
import random

#
CONF = {"min_occurence": 5, "max_occurence": 50, "min_length": 2}


def get_args():
    """
    Get args from stdin.
    """
    parser = argparse.ArgumentParser(
        description="""Finds canditate sentences to remove from the text corpus to create and OOV setting""",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )

    parser.add_argument(
        "--test_set",
        type=str,
        required=True,
        help="Path to the kaldi test text file set e.g. samromur/test/text",
    )

    parser.add_argument(
        "--text_corpus",
        type=str,
        required=True,
        help="Path to the text corpus used to train the language models",
    )

    parser.add_argument(
        "--data_dir",
        type=str,
        required=True,
        help="Path to the root dir where the folder 'experiment' will be located",
    )

    parser.add_argument(
        "--starting_oov_rate",
        type=float,
        default=0.005,
        help="The OOV rate for the first group of words in the experiment",
    )

    parser.add_argument(
        "--increase",
        type=float,
        default=0.005,
        help="""The amount the OOV rate incrementally increses between groups""",
    )

    parser.add_argument(
        "--num_groups",
        type=int,
        default=5,
        help="""The number of groups of oov candidate words created""",
    )

    parser.add_argument(
        "--num_sets_in_group",
        type=int,
        default=5,
        help="""The number of sets of candidate words for each incremation of the OOV rate. The increment 
        is repeated a few times to average out any anomalies that might occur when removing words in the
        training corpus.""",
    )

    parser.add_argument(
        "--n_jobs",
        type=int,
        default=1,
        help="""Number of jobs to run in parallel.""",
    )
    print(" ".join(sys.argv))

    return process_args(parser.parse_args())


def process_args(args) -> Tuple[argparse.ArgumentParser, Dict]:
    """
    A function that takes in the arguments and returns them along with processed information
    """

    paths = {
        "FREQ_DIR": os.path.join(args.data_dir, "word_frequncy_files"),
        "CAND_DIR": os.path.join(args.data_dir, "candidate_output"),
    }

    _set_up_paths(paths)
    return (args, paths)


def _set_up_paths(PATHS: dict) -> None:
    """
    Takes in a dictinary where the values are paths and creates the folders if they don't exists"
    """
    for x in PATHS.values():
        if not os.path.exists(x):
            os.mkdir(x)


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


def create_frequncy_files(PATHS: dict, args) -> None:
    """
    Creates a file with the frequncy
    """
    text_corpus_freq_out_path = os.path.join(PATHS["FREQ_DIR"], "text_corpus")
    if _check_if_file_exists(text_corpus_freq_out_path):
        text_freq = _count_freq(args.text_corpus)
        with open(text_corpus_freq_out_path, mode="w", encoding="utf-8") as f_out:
            for line in text_freq:
                f_out.write(f"{line[0]} {int(line[1])}\n")

    test_corpus_freq_out_path = os.path.join(PATHS["FREQ_DIR"], "test_corpus")
    if _check_if_file_exists(test_corpus_freq_out_path):
        test_freq = _count_freq(args.test_set, contains_id=True)
        with open(test_corpus_freq_out_path, mode="w", encoding="utf-8") as f_out:
            for line in test_freq:
                f_out.write(f"{line[0]} {int(line[1])}\n")


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


def _character_sanity_check(PATHS: str) -> None:
    """
    Finds all unique characters in the text corpus and checks if there are any foraign
    characters in the test set.
    """
    text_freq = _read_freq_file_as_list(os.path.join(PATHS["FREQ_DIR"], "text_corpus"))
    test_freq = _read_freq_file_as_list(os.path.join(PATHS["FREQ_DIR"], "test_corpus"))
    legal_chars = set()
    for line in text_freq:
        for char in line[0]:
            legal_chars.add(char)
    print(f"Chars in text corpus: {' '.join(sorted(list(legal_chars)))}")
    ilegal_chars = []
    for line in test_freq:
        for char in line[0]:
            if char not in legal_chars:
                ilegal_chars.append(char)

    if ilegal_chars:
        raise Exception(
            f"Found characters in test set that are not in train: {' '.join(sorted(ilegal_chars))}"
        )


def _get_sum_of_words_from_freq(word_freq: list, index: int = 1) -> int:
    """
    Returns the number of words in a set given a frequncy file
    """
    if word_freq:
        return sum([int(w[index]) for w in word_freq])
    else:
        return 0


def _get_num_words_to_remove(oov_rate: float, total_vocab: int) -> float:
    """
    Returns the number of words that would have to be removed
    given a desired OOV rate and the number of words in set
    """
    return math.ceil(total_vocab * float(oov_rate))


def _filter_based_on_threshold(word_freq: list) -> list:
    """
    Returns a new frequncy list where words that don't meet the requirements set
    in CONF are removed.
    """
    new_word_freq: list = []
    for word, freq in word_freq:
        if (
            int(freq) >= CONF["min_occurence"]
            and int(freq) <= CONF["max_occurence"]
            and len(word) >= CONF["min_length"]
        ):
            new_word_freq.append([word, freq])
    return new_word_freq


def _split_candiates_into_sets(cand: list, num_sets: int) -> list:
    """
    Takes in the number sets to create and splits the candidate words equally in those sets.
    Returns a list with "num_sets" lists that have [word-frequncy]
    """
    random.shuffle(cand)
    num_in_chunk = math.ceil(len(cand) / num_sets)
    cand = list(_chunks(cand, num_in_chunk))
    return cand


def _chunks(lst: list, n: int):
    """Yield successive n-sized chunks from lst."""
    for i in range(0, len(lst), n):
        yield lst[i : i + n]


def _create_set(cand: list, num_words_to_remove: int) -> list:
    """
    Given the number
    """
    candiates = []
    for cand_set in cand:
        words, sum_words, num_words_left = [], 0, num_words_to_remove
        while sum_words < num_words_to_remove:
            if ((num_words_left) / num_words_to_remove) <= CONF[
                "max_occurence"
            ] / num_words_to_remove and any(
                [int(x[1]) == num_words_left for x in cand_set]
            ):
                for x in cand_set:
                    if int(x[1]) == num_words_left:
                        w = x
                        break
            else:
                w = random.choice(cand_set)
            words.append(w)
            cand_set.remove(w)
            sum_words = _get_sum_of_words_from_freq(words)
            num_words_left = num_words_to_remove - sum_words
        candiates.append(words)
    return candiates


def save_candidates(candidates: list, path: str) -> None:
    """
    save each set of candidate words
    """
    if not os.path.exists(path):
        os.mkdir(path)
    for ind, cand_set in enumerate(candidates):
        f_name = os.path.join(path, str(ind + 1))
        with open(f_name, mode="w", encoding="utf-8") as f_out:
            for item in cand_set:
                f_out.write("\t".join([str(x) for x in item]) + "\n")


def _get_stats(cand_set: list, ind: int, num_words_to_remove: int) -> list:
    """
    A function to get a list of statas
    """
    sum_in_set = _get_sum_of_words_from_freq(cand_set)
    diff = f"{round(abs(1-(sum_in_set/num_words_to_remove))*100, 2)}%"
    return [f"set {ind+1}:", len(cand_set), sum_in_set, num_words_to_remove, diff]


def find_candidate_words(PATHS: dict, args) -> None:
    """
    The main function of this script. THi
    """

    print(f"Creating {args.num_groups} groups of sets")
    test_freq = _read_freq_file_as_list(os.path.join(PATHS["FREQ_DIR"], "test_corpus"))

    num_words_in_test = _get_sum_of_words_from_freq(test_freq)

    print(f"Total number of words in the test set: {num_words_in_test}")
    candidates_filtered = _filter_based_on_threshold(test_freq)
    print(
        f"Total number of words after removing based on CONF: {_get_sum_of_words_from_freq(candidates_filtered)}"
    )
    print(f"CONF={CONF}")
    oov_rates = [
        args.starting_oov_rate + args.increase * i for i in range(args.num_groups)
    ]

    for ind, oov_rate in enumerate(oov_rates):
        print(f"\nOOV rate: {oov_rate*100:.2}%")
        num_words_to_remove = _get_num_words_to_remove(oov_rate, num_words_in_test)
        candidates = _split_candiates_into_sets(
            candidates_filtered, args.num_sets_in_group
        )
        candidates_sets = _create_set(candidates, num_words_to_remove)

        print(f"Set\tnum-unique-words\tsum-of-words-in-set\tgoal\tdiff")
        for inner_ind, cand_set in enumerate(candidates_sets):
            s = _get_stats(cand_set, inner_ind, num_words_to_remove)
            print("\t".join([str(item) for item in s]))

        path = os.path.join(PATHS["CAND_DIR"], f"group_{str(ind+1)}_{str(oov_rate)}")
        save_candidates(candidates_sets, path)


def main():
    (args, paths) = get_args()

    create_frequncy_files(paths, args)
    _character_sanity_check(paths)

    find_candidate_words(paths, args)


if __name__ == "__main__":
    """
    This script takes in the text corpus and the test set in the kaldi format [id-sentenece] and 
    creates n many sets of words that will be removed from the text corpus to artifically create
    an out-of-vocabulary words in the test set. The oov rate starts 0.05% and increases incrementally as desired. 

    Run example:
    ./run/03_setup_experiment.py \
        --test_set /scratch/derik/subword_journal/isl/data/samromur/test/text \
        --data_dir /scratch/derik/subword_journal/isl/ \
        --text_corpus /scratch/derik/subword_journal/isl/text_corpora/rmh_2020-11-23+sm+malromur+althingi_sorted_cleaned_1m
        
    """
    main()
