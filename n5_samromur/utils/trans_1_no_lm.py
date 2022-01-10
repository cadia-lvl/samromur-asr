#-*- coding: utf-8 -*- 
########################################################################
#trans_1_no_lm.py

#Author   : Carlos Daniel Hernández Mena
#Date     : December 12nd, 2021
#Location : Reykjavík University

#Usage:

#	$ python3 utils/trans_1_no_lm.py <pretrained_nemo_model> <audio_in>

#Example:

#	$ python3 utils/trans_1_no_lm.py $nemo_model $audio_in

#Description:

#This is an example of how to transcribe 1 audio 
#with no language model.

#Notice: This program is intended for Python 3
########################################################################
#Imports

import sys
import os

import nemo
import nemo.collections.asr as nemo_asr

########################################################################
#Input Parameters

PRETRAINED_MODEL=sys.argv[1]

AUDIO_IN=sys.argv[2]

########################################################################

# Loading the pretrained model 
nemo_asr_model = nemo_asr.models.EncDecCTCModel.restore_from(PRETRAINED_MODEL)

########################################################################
# Decoding N audio files
list_audios=[AUDIO_IN]

for wav_file, transcription in zip(list_audios, nemo_asr_model.transcribe(paths2audio_files=list_audios, batch_size=1)):
	print("\n+++++++++++++++++++++++++++++++++++++++++++++")
	print(f"Audio in {wav_file} was recognized as: {transcription}")	 
	print("+++++++++++++++++++++++++++++++++++++++++++++\n")
#ENDFOR

########################################################################

