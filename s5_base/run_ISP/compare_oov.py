#!/usr/bin/env python3

# In this script we will run through the results of the subword decoding
# and examine how it performed on the oov's that we found with oov.py
# Author: David Erik Mollberg

import json
import sys
from os.path import join


def read_decode_file(decode_file):
    """
    Read the per_utt file and adds its content to a dict.

    We have four lines for each utterance. Lets load it into a dict where the key is the id and has a dict with three keys 
    key=id: {ref:list, hyp:list, op:list}
    """
    tmp:dict = {}
    with open(decode_file) as decode_results:
        for line in decode_results: 
            id = line.split()[0]
            type = line.split()[1]
            content = line.split()[2:]
            
            if id not in tmp:
                tmp[id] = {}
            tmp[id][type] = content
    return tmp

def drop_non_oov_utterances(decode_dict:dict, oovs:set):
    """
    Let's drop the utterances that we are not interested in 
    """
    new_dict= {}
    for key, value in decode_dict.items():
        if any(word in oovs for word in value['ref']):
            new_dict[key]=value
    return new_dict

def analize_per_word(decode_dict:dict, oovs:set, output_dict:dict):
    """
    Let's analize each utterance that has an oov in them.
    """
    output_dict:dict = {"per_word":{}, "total":{}}
    for key, value in decode_dict.items():
        for index, word in enumerate(value["ref"]):
            if word in oovs:
                # Init for word
                if word not in output_dict["per_word"]:
                    output_dict["per_word"][word] = {"id":[], "correct_transcription":0, "incorrect_transcription":0, "type_of_error": [], "surrounding_hyp":[]}

                output_dict["per_word"][word]["id"].append(key)
                # case 1: If hyp and ref are the same we correctly transcriped the oov
                if value["ref"] == value["hyp"]:
                    output_dict["per_word"][word]["correct_transcription"] += 1
                
                # case 2: if the oov is in hyp then we have a correct transcription 
                elif word in value['hyp']:
                    output_dict["per_word"][word]["correct_transcription"] += 1

                elif word not in value["hyp"]:
                    output_dict["per_word"][word]["incorrect_transcription"] += 1
                    output_dict["per_word"][word]["type_of_error"].append(value["op"][index])
                    if index in [0,1]:
                        output_dict["per_word"][word]["surrounding_hyp"].append(" ".join(value["hyp"][0:3]))
                    elif index in [len(value["hyp"])-1, len(value["hyp"])-2, len(value["hyp"])]:
                        output_dict["per_word"][word]["surrounding_hyp"].append(" ".join(value["hyp"][len(value["hyp"])-3:len(value["hyp"])]))
                    else:
                        output_dict["per_word"][word]["surrounding_hyp"].append(" ".join(value["hyp"][index-2: index+2]))
                else:
                    print("\n\n Nothing should be here")
                    quit()
    return output_dict

def get_total(decode_dict):
    """
    Get total number of correct and incorrect transcriptions of oovs
    """
    total_correct=0
    total_incorrect=0
    for key, value in decode_dict['per_word'].items():
        total_correct+=value["correct_transcription"]
        total_incorrect+=value["incorrect_transcription"]

    return total_correct, total_incorrect


def write_full_report(stats:dict, path:str):
    """
    Write the entire report to files
    """
    output=json.dumps(stats, indent=4, ensure_ascii=False)
    with open(path+".json", 'w') as f_out:
        f_out.write(output)


if __name__ == "__main__":
    
    subword_path="/home/derik/work/samromur-asr/s5_subwords/exp_ISP/isl"
    oov_path="/home/derik/work/samromur-asr/s5_base/data_ISP/sm"
    base_path="/home/derik/work/samromur-asr/exp_ISP/isl"

    for hours in ["10h", "20h", "40h", "80h", "160h", "320h"]:
        total_correct, total_incorrect = 0,0

        for decode_set in ["sm_dev_hires", "sm_test_hires", "althingi_dev_hires", "althingi_test_hires"]:

            #oovs_file=sys.argv[1]
            #decode_subword_file=sys.argv[2]
            #report_path=sys.argv[3]
            oovs_file=join(oov_path, decode_set, "oov")
            map:dict = {"sm_dev_hires": "decode_sm_dev_8g_rescored",\
                         "sm_test_hires": "decode_sm_test_8g_rescored",\
                         "althingi_dev_hires": "decode_althingi_dev_8g_rescored", \
                         "althingi_test_hires": "decode_althingi_test_8g_rescored"}

            decode_subword_file =join(subword_path, hours, "chain", f"tdnn{hours}_sp", f"{map[decode_set]}", "scoring_kaldi", "wer_details", "per_utt")

            oovs:set = set([x.rstrip() for x in open(oovs_file)])
            
            decode_subwords:dict = read_decode_file(decode_subword_file)

            decode_subwords= drop_non_oov_utterances(decode_subwords, oovs)
            stats:dict = {}
            stats = analize_per_word(decode_subwords, oovs, stats)

            #stats['total'] = get_total(stats)
            total_correct += get_total(stats)[0]
            total_incorrect += get_total(stats)[1]
            
            #print(json.dumps(stats, indent=4, ensure_ascii=False))

            
            # This  is a sanity check

            #decode_base_file=sys.argv[3]
            
            # decode_base =join(subword_path, hours, "chain", f"tdnn{hours}_sp", f"{map[decode_set]}", "scoring_kaldi", "wer_details", "per_utt")

            # decode_base:dict = read_decode_file(decode_base)
            # stats_base:dict={}
            # stats_base = analize_per_word(decode_base, oovs, stats_base)

            # for key, value in stats_base['per_word'].items():
            #     if value["correct_transcription"] != 0:
            #         print(decode_set, hours)
            #         print(key)
            #         print(f"This should never be printed. The base model was able to correctly transcripe the word {key}")

        print(f"{hours}\ntotal incorrect: {total_correct}\ntotal_correct: {total_incorrect}")
        print(f"{total_correct+total_incorrect}")
        #report_path=join("reports", hours)
        #write_full_report(stats, report_path)
