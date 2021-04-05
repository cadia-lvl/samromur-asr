#!/usr/bin/env python

import sys
import shutil


text_file=sys.argv[1]


with open("tmp", 'w') as f_out, open(text_file) as f_in:
    for line in f_in:
        line = line.rstrip()
        id = line.split(' ')[0]
        s = ' '.join(line.split(' ')[1:])
        s = s.lower()
        f_out.write(f"{id} {s}\n")


shutil.move("tmp", text_file)