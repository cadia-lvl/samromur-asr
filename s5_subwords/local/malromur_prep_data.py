#!/usr/bin/env python3

# Author David Erik Mollberg davidemollberg@gmail.com
# Apache 2.0


from os.path import exists, join
from os import makedirs, getcwd
import subprocess
import argparse

def sort_and_write(datadir:str, data:list):
    '''
    Write the files given a file name and a list. 
    The list will is sorted before writing.
    '''
    with open(datadir, 'w') as f_out:
        for line in data:
            f_out.write(line) 


def append_to_file(i, text, wavscp, utt2spk, spk2gender):
    '''
    Append relevant data to the lists
    '''

    utt_id=f[0]
    text.append(f"{utt_id} {f[9]}\n")
    wavscp.append(f"{utt_id} sox - -c1 -esigned -r {f[7]} -twav - < {join(args.audio, f[1])} |\n")
    utt2spk.append(f"{utt_id} {f[2]}\n")
    
    #This line will cause an error in versions of Samrómur where the speaker is unknown
    if f[3][0] == 'f':
        gender = 'f'
    elif f[3][0] == 'm':
        gender = 'm'
    else:
        gender = 'f'

    spk2gender.append(f"{f[2]} {gender}\n")

def clean_dir(datadir):
    subprocess.call(f"utils/utt2spk_to_spk2utt.pl < {datadir}/utt2spk > {datadir}/spk2utt", shell=True)
    subprocess.call(f"utils/validate_data_dir.sh --no-feats {datadir} || utils/fix_data_dir.sh {datadir}", shell=True)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="\nUsage: $0 <path-to-audio> <audio-meatadata-file> <create_kaldi_id's> \
        This script will output the files text, wav.scp, utt2spk, spk2utt and spk2gender \
        to data/all, data/train data/test with test/train/eval splits defined in the metadatafile. \
        The script also makes a tokens file which which contains the lexicon in a the corpus \
        Eg. samromur_prep_data.py /data/corpora/samromur/audio/ metadata.tsv\n")
        
    parser.add_argument("-a","--audio", required=True, type=str,
                        help="Path to audio corpus")
    parser.add_argument("-m","--metadata", required=True, type=str,
                        help="Path to the metadatafile")
    parser.add_argument("-o","--output_dir", required=True, type=str,
                        help="Use to distinguish between different runs")
                        
    args = parser.parse_args()

    for data_file in ['train', 'dev', 'test']:
        datadir = join(args.output_dir, data_file)
        print(f'Creating files in {datadir}')

        text, wavscp, utt2spk, spk2gender = [], [], [], []
        tokens = set()
        with open(args.metadata) as f_in:
            f_in.readline()
            for line in f_in:
                f = line.split('\t')
                if data_file =='train' and f[10] == 'training':
                    append_to_file(f, text, wavscp, utt2spk, spk2gender)
                elif data_file == 'dev' and f[10] == 'test':
                    append_to_file(f, text, wavscp, utt2spk, spk2gender)    
                elif data_file == 'test' and f[10] == 'test':
                    append_to_file(f, text, wavscp, utt2spk, spk2gender)  

                for tok in f[9].split(' '):
                    tokens.add(tok.rstrip())

        #If empty there might not be an evaluation set, 
        #no need to create an folder with empty files.
        if text:
            data = zip([text, wavscp, utt2spk, spk2gender], ['text', 'wav.scp', 'utt2spk', 'spk2gender'])
            if not exists(datadir):
                makedirs(datadir)

            for d, name in data:
                name = join(datadir, name)
                sort_and_write(name, d)

            with open(join(datadir, 'tokens'), 'w') as f_out:
                for tok in sorted(list(tokens)):
                    if len(tok) > 0:
                        f_out.write(tok+'\n')

            clean_dir(datadir)