#!/usr/bin/env python3
#-*- coding: utf-8 -*-

# Copyright 2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

from nltk.tokenize import word_tokenize
    
import codecs
import re
import sys

WORD = '<word>'


def process_line(line,oovlist):

    tokens = word_tokenize(line)
    output_tokens = []
    word_list = [tokens[0]]
    
    for token in tokens:
        if token in oovlist:
            output_tokens.append(WORD)
            word_list.append(token)
        else:
            output_tokens.append(token)

    return [" ".join(output_tokens) + " ", word_list]


with codecs.open(sys.argv[4], 'w', 'utf-8') as OOVlist_out:
    with codecs.open(sys.argv[3], 'w', 'utf-8') as out_txt:
        with codecs.open(sys.argv[2], 'r', 'utf-8') as OOVlist_in:
            with codecs.open(sys.argv[1], 'r', 'utf-8') as text:

                oovlist = OOVlist_in.read().splitlines()
                for line in text:
                    line, mapped_words = process_line(line,oovlist)

                    out_txt.write(line + '\n')
                    if len(mapped_words) > 1:
                         OOVlist_out.write(" ".join(mapped_words) + '\n')

