#-*- coding: utf-8 -*- 
########################################################################
#inference_no_lm.py

#Author   : Carlos Daniel Hernández Mena
#Date     : December 06th, 2021
#Location : Reykjavík University

#Usage:

#	$ python3 inference_no_lm.py <num_jobs> <experiment_path> <arch_conf_file> <manifest_path> <training_dir>

#Example:

#    python3 $exp_dir/inference_no_lm.py $nj_decode $exp_dir \
#                                        conf/Config_QuartzNet15x5_Icelandic.yaml \
#                                        data/test/test_manifest.json \
#                                        exp/model_training

#Description:

#This script transcribes the audio files specified in the
#input manifest. It doesn't no use language model.

#Notice: This program is intended for Python 3
########################################################################
#Imports

import sys
import re
import os

import nemo
import nemo.collections.asr as nemo_asr

########################################################################
#Input Parameters

NUM_JOBS=int(sys.argv[1])

EXPERIMENT_PATH=sys.argv[2]

CONFIG_PATH=sys.argv[3]

MANIFEST_PATH=sys.argv[4]

TRAINING_DIR=sys.argv[5]

########################################################################
#Important Variable and Paths

final_model_pointer=os.path.join(TRAINING_DIR,"final_model.path")
file_pointer=open(final_model_pointer,'r')
model_checkpoint=file_pointer.read()
model_checkpoint=model_checkpoint.replace("\n","")
file_pointer.close()

manifest_name=os.path.basename(MANIFEST_PATH)
lista_manifest=manifest_name.split("_")
PORTION=lista_manifest[0]

########################################################################
# Loading the pretrained model 

nemo_asr_model = nemo_asr.models.EncDecCTCModel.restore_from(model_checkpoint)

########################################################################
# Reading Model definition
from ruamel.yaml import YAML

config_path = sys.argv[4]

yaml = YAML(typ='safe')
with open(CONFIG_PATH) as f:
    model_definition = yaml.load(f)
#ENDWITH

########################################################################
#Extract the audio list and reference transcripts from the json file

import json

manifest_in=open(MANIFEST_PATH,'r')

audio_list=[]
id_list=[]
ref_trans_list=[]

hash_line = {}
for linea in manifest_in:
	linea = linea.replace("\n","")
	hash_line = json.loads(linea)

	audio_filepath = hash_line['audio_filepath']
	duration = hash_line['duration']

	text = hash_line['text']
	text = re.sub('\s+',' ',text)
	text = text.strip()

	audio_list.append(audio_filepath)
	
	audio_id=os.path.basename(audio_filepath)
	audio_id=audio_id.replace(".wav","")
	id_list.append(audio_id)
	
	trans_out=audio_id+" "+text
	ref_trans_list.append(trans_out)
#ENDFOR
manifest_in.close()

########################################################################
#Writing the reference transcriptions in an output file
trans_file_name=PORTION+"_reference.trans"
trans_file_path=os.path.join(EXPERIMENT_PATH,trans_file_name)
ref_trans=trans_file_path
file_trans=open(trans_file_path,"w")
for trans in ref_trans_list:
	file_trans.write(trans+"\n")
#ENDFOR
file_trans.close()

########################################################################
#Generating the hyphotesis transcriptions
trans_file_name=PORTION+"_hypothesis.trans"
trans_file_path=os.path.join(EXPERIMENT_PATH,trans_file_name)
file_trans=open(trans_file_path,"w")

index=-1
for trans in nemo_asr_model.transcribe(paths2audio_files=audio_list,batch_size=NUM_JOBS):
	index=index+1
	current_id=id_list[index]
	line_out=current_id+" "+trans
	line_out=re.sub("\s+"," ",line_out)
	line_out=line_out.strip()
	file_trans.write(line_out+"\n")
#ENDFOR
file_trans.close()

########################################################################
#Calculating the WER

# Bigger batch-size = bigger throughput
model_definition['model']['validation_ds']['batch_size'] = NUM_JOBS
#Passing the path of the test manifest to the model
model_definition['model']['validation_ds']['manifest_filepath'] = MANIFEST_PATH

# Setup the test data loader and make sure the model is on GPU
nemo_asr_model.setup_test_data(test_data_config=model_definition['model']['validation_ds'])
nemo_asr_model.cuda()

# We will be computing Word Error Rate (WER) metric between our hypothesis and predictions.
# WER is computed as numerator/denominator.
# We'll gather all the test batches' numerators and denominators.
wer_nums = []
wer_denoms = []

# Loop over all test batches.
# Iterating over the model's `test_dataloader` will give us:
# (audio_signal, audio_signal_length, transcript_tokens, transcript_length)
# See the AudioToCharDataset for more details.
for test_batch in nemo_asr_model.test_dataloader():
        test_batch = [x.cuda() for x in test_batch]
        targets = test_batch[2]
        targets_lengths = test_batch[3]        
        log_probs, encoded_len, greedy_predictions = nemo_asr_model(
            input_signal=test_batch[0], input_signal_length=test_batch[1]
        )
        # Notice the model has a helper object to compute WER
        nemo_asr_model._wer.update(greedy_predictions, targets, targets_lengths)
        _, wer_num, wer_denom = nemo_asr_model._wer.compute()
        wer_nums.append(wer_num.detach().cpu().numpy())
        wer_denoms.append(wer_denom.detach().cpu().numpy())
#ENDFOR

# We need to sum all numerators and denominators first. Then divide.
wer=str(round(100.0*(sum(wer_nums)/sum(wer_denoms)),2))
line_wer="WER ("+PORTION+") = "+wer+"%"

file_wer_path=os.path.join(EXPERIMENT_PATH,"best_wer")
file_wer=open(file_wer_path,"w")
file_wer.write(line_wer)
file_wer.close()

#Inform to user
print("\n")
print("######################################")
print(line_wer)
print("######################################")

########################################################################

print("\nINFO: ("+PORTION+") Hyphothesis transcriptions in file: "+trans_file_path)
print("INFO: ("+PORTION+") Reference transcriptions in file  : "+ref_trans)
print("INFO: ("+PORTION+") Best WER registered in            : "+file_wer_path)

########################################################################

print("\nINFO: INFERENCE WITH NO LANGUAGE MODEL SUCCESFULLY DONE!")

########################################################################

