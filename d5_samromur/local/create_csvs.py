#-*- coding: utf-8 -*- 
########################################################################
#create_csvs.py

#Author   : Carlos Daniel Hernández Mena
#Date     : January 01st, 2022
#Location : Reykjavík University

#Usage:

#	$ python3 create_csvs.py <path_to_wav_version_of_samrómur>

#Example:

#	$ python3 local/create_csvs.py $corpus_wav_path/$corpus_wav_name

#Description:

#This script create the CSV files for train, dev and test required
#by DeepSpeech

#Notice: This program is intended for Python 3
########################################################################
#Imports

import sys
import re
import os
import pandas as pd

########################################################################
#Determine the Byte size of a file

def get_byte_size(ruta_archivo_in):
	file_stats=os.stat(ruta_archivo_in)
	byte_size=file_stats.st_size
	return byte_size
#ENDDEF

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
				'status']
)

#----------------------------------------------------------------------#
#Creating the output CSV files
train_csv=open("train.csv","w")
test_csv=open("test.csv","w")
dev_csv=open("dev.csv","w")

#----------------------------------------------------------------------#
#Writing the header to the output CSV files

header="wav_filename,wav_filesize,transcript"

train_csv.write(header+"\n")
test_csv.write(header+"\n")
dev_csv.write(header+"\n")

#----------------------------------------------------------------------#   
#Iterating the Pandas Data Frame and creating the output CSVs.

for index,row in metadata_file.iterrows():
	filename=row['filename']
	sentence_norm=row['sentence_norm']
	status=row['status']
	
	audio_path=hash_paths[filename]
		
	#File size in Bytes
	file_size=get_byte_size(audio_path)

	line_out=audio_path+","+str(file_size)+","+sentence_norm
		
	if status=="train":
		train_csv.write(line_out+"\n")
	elif status=="test":
		test_csv.write(line_out+"\n")
	elif status=="dev":
		dev_csv.write(line_out+"\n")
	#ENDIF
#ENDFOR

########################################################################
#Close the open files
train_csv.close()
test_csv.close()
dev_csv.close()

########################################################################

