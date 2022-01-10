#-*- coding: utf-8 -*- 
########################################################################
#create_manifests.py

#Author   : Carlos Daniel Hernández Mena
#Date     : December 04th, 2021
#Location : Reykjavík University

#Usage:

#	$ python3 create_manifests.py <path_to_wav_version_of_samrómur>

#Example:

#	$ python3 local/create_manifests.py $corpus_wav_path/$corpus_wav_name

#Description:

#This script create the manifest for train, dev and test required by NeMo.

#Notice: This program is intended for Python 3
########################################################################
#Imports

import sys
import re
import os
import pandas as pd

########################################################################
#Creating a list of absolut paths of the audio files

CORPUS_PATH=sys.argv[1]

hash_paths={}

for root, dirs, files in os.walk(CORPUS_PATH):
	for filename in files:
		if filename.endswith(".wav"):
			wav_path=os.path.join(root,filename)
			hash_paths[filename]=wav_path
		#ENDIF
	#ENDFOR
#ENDFOR

########################################################################
#Columns of the Samrómur Metadata File

#id
#speaker_id
#filename
#sentence
#sentence_norm
#gender
#age
#native_language
#dialect
#created_at
#marosijo_score
#release
#is_valid
#empty
#duration
#sample_rate
#size
#user_agent
#status

########################################################################
#Infering the full path of the input metadata file.
metadata_path=os.path.join(CORPUS_PATH,'metadata.tsv')

########################################################################
#Reading the metadata file with Pandas.

metadata_file=pd.read_csv(metadata_path,
				sep='\t',
				header=0,
				low_memory=False,
				usecols=['filename',
				'sentence_norm',
				'duration',
				'status']
)

#----------------------------------------------------------------------#                    
#Iterating the Pandas Data Frame and creating the output Jasons.

train_json=open("train_manifest.json","w")
test_json=open("test_manifest.json","w")
dev_json=open("dev_manifest.json","w")

for index,row in metadata_file.iterrows():
	filename=row['filename']
	sentence_norm=row['sentence_norm']
	duration=row['duration']
	status=row['status']
	
	audio_path=hash_paths[filename]

	json_line="{\"audio_filepath\": \""+audio_path+"\", "+"\"duration\": "+str(duration)+", \"text\": \""+sentence_norm+"\"}"
	
	if status=="train":
		train_json.write(json_line+"\n")
	elif status=="test":
		test_json.write(json_line+"\n")
	elif status=="dev":
		dev_json.write(json_line+"\n")
	#ENDIF
#ENDFOR

#Close the open files
train_json.close()
test_json.close()
dev_json.close()

########################################################################

