#!/usr/bin/env python3

# Copyright      2018  Ashish Arora
# Apache 2.0     2020  David Erik Mollberg

# This script prepares lexicon.

import argparse
import os
import sys
import re

parser = argparse.ArgumentParser(description="""Creates the list of characters and words in lexicon""")
parser.add_argument('--i', required=True, help='Path to grapheme_lexicon')
parser.add_argument('--o', required=True, help='Output path')
parser.add_argument('--is_subword', default=False)

args = parser.parse_args()


### main ###
lex = {}
text_path = os.path.join(args.i)
with open(text_path, 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        characters = list(line)
        characters = " ".join(['V' if char == '*' else char for char in characters])
        if args.is_subword:
            characters = re.sub('@', '', characters)
        lex[line] = characters

with open(os.path.join(args.o), 'w', encoding='utf-8') as fp:
    for key, value in lex.items():
        if args.is_subword:
            fp.write(key+' '+value+ "\n")
        else:
            fp.write(key + "  " + " ".join(['V' if char == '*' else char for char in list(key)]) + "\n")
