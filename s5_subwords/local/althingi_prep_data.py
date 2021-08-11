#!/usr/bin/env python3

import sys, os

# Script to create wav.scp file for the althingi data. 

#AFE-rad20180306T191609 sox -tmp3 - -c1 -esigned -r16000 -G -twav -  < /data/asr/althingi/corpus_jun2018/audio/rad20180306T191609.mp3 |

reco2audio = sys.argv[1]
audio_dir = sys.argv[2]


with open(reco2audio) as f_in:

    for line in f_in:
        line = line.rstrip()
        id, filename = line.split(' ') 
        audio_file=os.path.join(audio_dir, filename)
        conversion_command=' sox -tmp3 - -c1 -esigned -r16000 -G -twav - < '
        print(id + conversion_command + audio_file + ' |')




