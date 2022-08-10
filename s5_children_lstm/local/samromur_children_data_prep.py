#-*- coding: utf-8 -*- 
########################################################################
#samromur_children_data_prep.py

#Author   : Carlos Daniel Hernández Mena
#Date     : October 13rd, 2021
#Location : Reykjavík University

#Example of use:

#	$ python3 samromur_children_data_prep.py <samromur_children_directory>

#Specific example:

#	$ python3 samromur_children_data_prep.py /mnt/Datos/CORPUS/samromur_children_ldc

#Description:

#This script is part of Kaldi recipe.

#In this recipe only children from 4 to 12 years are considered.

#Notice: This program is intended for Python 3
########################################################################
#Imports

import sys
import os
import re
import pandas as pd

########################################################################
#Reading the metadata file which is in a TSV format.

CORPUS_ROOT=sys.argv[1]
metadata_file=os.path.join(CORPUS_ROOT,"metadata.tsv")
metadata=pd.read_csv(metadata_file,
                     sep='\t',
                     header=0,
                     low_memory=False,
                     usecols=['filename',
                              'sentence_norm',
                              'gender',
                              'age',
                              'status']
                    )

########################################################################
#Extracting relevant information from the metadata file.
#In this stage, the information is loaded in memory through
#python objetcs such like hashes or lists.

hash_train_trans={}
hash_train_gender={}
list_train_keys=[]

hash_test_trans={}
hash_test_gender={}
list_test_keys=[]

hash_dev_trans={}
hash_dev_gender={}
list_dev_keys=[]

#Iterating the pandas dataframe
for index,row in metadata.iterrows():
	age=row['age']
	if age.isnumeric()==True:
		if int(age) <= 12:
			filename=row["filename"]
			filename=filename.replace(".flac","")
			
			list_filename=filename.split("-")
			speaker=list_filename[0]
			
			sentence_norm=row['sentence_norm']
			
			gender=row['gender']
			gender=gender.replace("male","m")
			gender=gender.replace("fem","f")
			gender=gender.replace("other","f")
			gender=gender.replace("NAN","f")
			
			status=row['status']
			
			if status=="train":
				hash_train_trans[filename]=sentence_norm
				hash_train_gender[speaker]=gender
				list_train_keys.append(filename)
			elif status=="test":
				hash_test_trans[filename]=sentence_norm
				hash_test_gender[speaker]=gender
				list_test_keys.append(filename)
			elif status=="dev":
				hash_dev_trans[filename]=sentence_norm
				hash_dev_gender[speaker]=gender
				list_dev_keys.append(filename)
			#ENDIF
		#ENDIF
	#ENDIF
#ENDFOR

#----------------------------------------------------------------------#
#Search audio files in the Corpus directory

hash_paths={}
	
for root, dirs, files in os.walk(CORPUS_ROOT):
	for filename in files:
		list_filename=filename.split(".")
		extension=list_filename[-1]
		if extension=="flac":
			key=filename.replace(".flac","")
			path=os.path.join(root, filename)
			hash_paths[key]=path
		#ENDIF
	#ENDFOR
#ENDFOR

########################################################################
#Creating output files
#In this stage, the information loaded in memory is used to create
#the output files required by Kaldi.
#The files have to be located in the s5/data directory.

#This function is used to create the data files depending
#on the desire portion (train, test or dev).
def create_data_files(PORTION, LIST_KEYS,HASH_TRANS,HASH_PATHS,HASH_GENDER):
	#Creating the data directory if needed.
	data_dir="data"
	if not os.path.exists(data_dir):
		os.mkdir(data_dir)
	#ENDIF
	
	#Creating the directory of the corresponding
	#portion (train,test,dev) if needed.
	portion_dir=os.path.join("data",PORTION)
	if not os.path.exists(portion_dir):
		os.mkdir(portion_dir)
	#ENDIF
	
	#Opening the files.
	file_text_path=os.path.join(portion_dir,"text")
	file_text=open(file_text_path,"w")

	file_wav_scp_path=os.path.join(portion_dir,"wav.scp")
	file_wav_scp=open(file_wav_scp_path,"w")
	
	file_utt2spk_path=os.path.join(portion_dir,"utt2spk")
	file_utt2spk=open(file_utt2spk_path,"w")

	file_spk2gender_path=os.path.join(portion_dir,"spk2gender")
	file_spk2gender=open(file_spk2gender_path,"w")
	
	LIST_KEYS.sort()
	for key in LIST_KEYS:
		#File "text".
		trans=HASH_TRANS[key]
		line_out=key+" "+trans
		line_out=re.sub('\s+',' ',line_out)
		line_out=line_out.strip()
		file_text.write(line_out+"\n")
		#File "utt2spk".
		list_key=key.split("-")
		speaker=list_key[0]
		linea_out=key+" "+speaker
		file_utt2spk.write(linea_out+"\n")
		#File "wav.scp".
		path=HASH_PATHS[key]
		line_out=key+" flac -c -d -s "+path+" |"
		file_wav_scp.write(line_out+"\n")
	#ENDFOR

	#File "spk2gender".
	list_gender=list(HASH_GENDER.items())
	list_gender.sort()
	for key,value in list_gender:
		line_out=key+" "+value
		file_spk2gender.write(line_out+"\n")
	#ENDFOR
	
	#Close the files
	file_text.close()
	file_wav_scp.close()
	file_spk2gender.close()
	file_utt2spk.close()
#ENDDEF
#----------------------------------------------------------------------#
#Train files
create_data_files("train",list_train_keys,hash_train_trans,hash_paths,hash_train_gender)
#----------------------------------------------------------------------#
#Test files
create_data_files("test",list_test_keys,hash_test_trans,hash_paths,hash_test_gender)
#----------------------------------------------------------------------#
#Dev files
create_data_files("dev",list_dev_keys,hash_dev_trans,hash_paths,hash_dev_gender)
########################################################################

