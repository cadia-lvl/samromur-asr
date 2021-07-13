#!/usr/bin/env python3

# Copyright     
# Apache 2.0     2020  David Erik Mollberg

# This script prepares a grapheme lexicon from a list of words. 
# example input ./prepare_lexicon.py < words > lexicon.txt

import sys

if __name__=='__main__':

    for line in sys.stdin:
        line = line.strip()
        characters = list(line)
        characters = " ".join([char for char in characters]).rstrip()
        characters = characters.replace('+', '')
        sys.stdout.write(line + ' ' + characters.strip() + "\n")