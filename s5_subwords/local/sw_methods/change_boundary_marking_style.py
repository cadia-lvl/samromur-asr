#!/usr/bin/env python3


import sys


text_file = sys.argv[1] 
bm = sys.argv[2] # boundary marking style
sep = sys.argv[3] # Subword separator

with open(text_file) as f_in:
    for line in f_in:
        line = line.rstrip()
        if bm == "l":
            print(line.replace(f'{sep} ', f' {sep}'))
        elif bm == "lr":
            print(line.replace(f'{sep} ', f'{sep} {sep}'))
        elif bm == "wb":
            line = line.replace(f'{sep} ', '<<TMP>>')
            line = line.replace(' ', f' {sep} ')
            line = line.replace(f'<<TMP>>', ' ')
            print(line)