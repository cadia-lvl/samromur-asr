#-*- coding: utf-8 -*- 
########################################################################
#inference_with_lm.py

#Author   : Carlos Daniel Hernández Mena
#Date     : December 12nd, 2021
#Location : Reykjavík University

#Usage:

#	$ python3 inference_with_lm.py <num_jobs> <experiment_path> <lm_path> <manifest_path> <training_dir>

#Example:

#    python3 $exp_dir/inference_with_lm.py $nj_decode $exp_dir $arpa_lm \
#                                          data/test/test_manifest.json \
#                                          exp/model_training

#Description:

#This script transcribes the audio files specified in the
#input manifest using a Language Model.

#Notice: This program is intended for Python 3
########################################################################
#Imports

import sys
import re
import os

import nemo
import nemo.collections.asr as nemo_asr
import numpy as np

########################################################################
#Input Parameters

NUM_JOBS=int(sys.argv[1])

EXPERIMENT_PATH=sys.argv[2]

LM_PATH=sys.argv[3]

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
#Extract the audio list and reference transcripts from the json file

import json

manifest_in=open(MANIFEST_PATH,'r')

audio_list=[]
id_list=[]
ref_trans_list=[]

REF_TEXT_LIST=[]
hash_line = {}
for linea in manifest_in:
	linea = linea.replace("\n","")
	hash_line = json.loads(linea)

	audio_filepath = hash_line['audio_filepath']
	duration = hash_line['duration']

	text = hash_line['text']
	text = re.sub('\s+',' ',text)
	text = text.strip()
	REF_TEXT_LIST.append(text)
	
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
#Create the Beam Search Object and load the Language Model
beam_search_lm = nemo_asr.modules.BeamSearchDecoderWithLM(
	vocab=list(nemo_asr_model.decoder.vocabulary),
	beam_width=16,
	alpha=2, beta=1.5,
	lm_path=LM_PATH,
	num_cpus=max(os.cpu_count(), 1),
	input_tensor=False)

########################################################################
#Extract logits

def softmax(logits):
	e = np.exp(logits - np.max(logits))
	return e / e.sum(axis=-1).reshape([logits.shape[0], 1])
#ENDDEF

########################################################################
#Generating the hyphotesis transcriptions
trans_file_name=PORTION+"_hypothesis.trans"
trans_file_path=os.path.join(EXPERIMENT_PATH,trans_file_name)
file_trans=open(trans_file_path,"w")

index=-1
HYP_TEXT_LIST=[]
for wav_file, current_logits in zip(audio_list, nemo_asr_model.transcribe(paths2audio_files=audio_list, logprobs=True,batch_size=NUM_JOBS)):
	index=index+1
	current_id=id_list[index]
	probs = softmax(current_logits)
	
	# Printing the best candidates for each audio file
	best_candidate=beam_search_lm.forward(log_probs = np.expand_dims(probs, axis=0), log_probs_length=None)[0][0]

	trans=best_candidate[-1]
	HYP_TEXT_LIST.append(trans)
	line_out=current_id+" "+trans
	line_out=re.sub("\s+"," ",line_out)
	line_out=line_out.strip()
	file_trans.write(line_out+"\n")	
#ENDFOR
file_trans.close()

########################################################################
# Calculating the WER
#Ver: https://github.com/NVIDIA/NeMo/blob/main/nemo/collections/asr/metrics/wer.py

from nemo.collections.asr.metrics import wer

# We use a nemo function to calculate the WER
wer=str(round(100*wer.word_error_rate(HYP_TEXT_LIST,REF_TEXT_LIST,False),2))
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

print("\nINFO: INFERENCE WITH LANGUAGE MODEL SUCCESFULLY DONE!")

########################################################################
