#-*- coding: utf-8 -*- 
########################################################################
#trans_1_with_lm.py

#Author   : Carlos Daniel Hernández Mena
#Date     : December 12nd, 2021
#Location : Reykjavík University

#Usage:

#	$ python3 utils/trans_1_with_lm.py <pretrained_nemo_model> <arpa_lang_model> <audio_in>

#Example:

#	$ python3 utils/trans_1_with_lm.py $nemo_model $arpa_lang_model $audio_in

#Description:

#This is an example of how to transcribe 1 audio 
#with an ARPA language model.

#Notice: This program is intended for Python 3
########################################################################
#Imports

import sys
import os

import nemo
import nemo.collections.asr as nemo_asr
import numpy as np

########################################################################
#Input Parameters

PRETRAINED_MODEL=sys.argv[1]

LANGUAGE_MODEL=sys.argv[2]

AUDIO_IN=sys.argv[3]

########################################################################
# Loading the pretrained model 
nemo_asr_model = nemo_asr.models.EncDecCTCModel.restore_from(PRETRAINED_MODEL)

########################################################################
#It could be a list of N audios.
list_audios=[AUDIO_IN]

########################################################################
# Instantiate BeamSearchDecoderWithLM module.

beam_search_lm = nemo_asr.modules.BeamSearchDecoderWithLM(
	vocab=list(nemo_asr_model.decoder.vocabulary),
	beam_width=16,
	alpha=2, beta=1.5,
	lm_path=LANGUAGE_MODEL,
	num_cpus=max(os.cpu_count(), 1),
	input_tensor=False)

########################################################################
# Softmax implementation in NumPy
def softmax(logits):
	e = np.exp(logits - np.max(logits))
	return e / e.sum(axis=-1).reshape([logits.shape[0], 1])
#ENDDEF

########################################################################
# Do inference without decoder
logits = nemo_asr_model.transcribe(list_audios, logprobs=True)[0]
probs = softmax(logits)

########################################################################
# Check all transcription candidates along with their scores.

print("\nCheck all transcription candidates along with their scores:")
for candidate_list in beam_search_lm.forward(log_probs = np.expand_dims(probs, axis=0), log_probs_length=None) :
	for candidate in candidate_list:
		print(candidate)
	#ENDFOR
#ENDFOR

########################################################################
# Print the best candidate (With the prob closest to zero)

print("\n+++++++++++++++++++++++++++++++++++++++++++++")
print("The best candidate in audio "+AUDIO_IN+" is:")
print(beam_search_lm.forward(log_probs = np.expand_dims(probs, axis=0), log_probs_length=None)[0][0] )
print("+++++++++++++++++++++++++++++++++++++++++++++\n")

########################################################################

