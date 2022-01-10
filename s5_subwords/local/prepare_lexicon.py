#!/usr/bin/env python3

# Copyright      2018  Ashish Arora
# Apache 2.0     2020  David Erik Mollberg

# This script prepares grapheme lexicons.

import argparse
import os
import sys
import re

def boolean_string(s):
    if s not in {'False', 'True'}:
        raise ValueError('Not a valid boolean string')
    return s == 'True'

parser = argparse.ArgumentParser(description="""Creates the list of characters and words in lexicon""")
parser.add_argument('--i', required=True, help='Path to grapheme_lexicon')
parser.add_argument('--o', required=True, help='Output path')
parser.add_argument('--is_subword', type=boolean_string, default=True, help='Set as false when using standard text')

args = parser.parse_args()

### main ###
with open(os.path.join(args.i), 'r', encoding='utf-8') as f:
    with open(os.path.join(args.o), 'w', encoding='utf-8') as fp:
        for line in f:
            line = line.strip()
            characters = list(line)
            characters = " ".join([char for char in characters])
            if args.is_subword:
                characters = re.sub('@', '', characters).rstrip()
            fp.write(line + ' ' + characters + "\n")