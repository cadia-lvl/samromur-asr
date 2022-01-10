#-*- coding: utf-8 -*- 
########################################################################
#flac2wav.py

#Author   : Carlos Daniel Hernández Mena
#Date     : December 04th, 2021
#Location : Reykjavík University

#Usage:

#	$ python3 flac2wav.py <samrómur_directory> <path_to_the_corpus_in_wav> <new_corpus_name>

#Example:

#	$ python3 local/flac2wav.py $corpus_root $corpus_wav_path $corpus_wav_name 

#Description:

#This script converts the input corpus in flac to wav.

#Notice: This program is intended for Python 3
########################################################################
#Imports

import sys
import re
import os
import multiprocessing

########################################################################
#Getting important paths

CORPUS_PATH_ORG=sys.argv[1]

name_corpus_org=os.path.basename(CORPUS_PATH_ORG)

name_corpus_dst=sys.argv[3]

CORPUS_PATH_DST=os.path.join(sys.argv[2],name_corpus_dst)

########################################################################
#Iterating the corpus directory

HASH_DIRS_ORG={}
HASH_DIRS_DST={}

for root, dirs, files in os.walk(CORPUS_PATH_ORG):
	for dir_name in dirs:
		dir_path_org=os.path.join(root,dir_name)
		dir_path_dst=dir_path_org.replace(name_corpus_org,name_corpus_dst)
		dir_path_dst=dir_path_org.replace(CORPUS_PATH_ORG,CORPUS_PATH_DST)
		HASH_DIRS_ORG[dir_path_org]=None
		HASH_DIRS_DST[dir_path_dst]=None
	#ENDFOR
#ENDFOR

#print(len(HASH_DIRS_ORG))
#print(len(HASH_DIRS_DST))

########################################################################
#Creating the output directories.

if not os.path.exists(CORPUS_PATH_DST):
	os.mkdir(CORPUS_PATH_DST)
#ENDIF

for directory in HASH_DIRS_DST:
	if not os.path.exists(directory):
		os.mkdir(directory)
	#ENDIF
#ENDFOR

########################################################################
#Collecting the audios paths

lista_iterable = []
for root, dirs, files in os.walk(CORPUS_PATH_ORG):
	for filename in files:
		if filename.endswith(".flac"):
			audio_path_org=os.path.join(root,filename)
			audio_path_dst=audio_path_org.replace(name_corpus_org,name_corpus_dst)
			audio_path_dst=audio_path_org.replace(CORPUS_PATH_ORG,CORPUS_PATH_DST)
			audio_path_dst=audio_path_dst.replace(".flac",".wav")
			lista_iterable.append([audio_path_org,audio_path_dst])
		#ENDIF
	#ENDFOR
#ENDFOR

#print(len(lista_iterable))

########################################################################
#Takes all the processors availables
NUM_PROCESSORS = multiprocessing.cpu_count()

########################################################################
#Parallel Function
def tarea_paralela_map(lista_task):
	ORG = lista_task[0]
	DST = lista_task[-1]
	if not os.path.exists(DST):	
		os.system("sox "+ORG+ " -c 1 -r 16000 --norm " +DST)
	#ENDIF
	return None
#ENDDEF

########################################################################
#Doing the conversion
if __name__ == '__main__':
	pool = multiprocessing.Pool(NUM_PROCESSORS)
	results =pool.map_async(tarea_paralela_map,lista_iterable)
	results.get()
#ENDIF

########################################################################
#Create the new metadata file in the directory of the output corpus.

metadata_name="metadata.tsv"

path_meta_out=os.path.join(CORPUS_PATH_DST,metadata_name)
metadadata_out=open(path_meta_out,'w')

path_meta_in=os.path.join(CORPUS_PATH_ORG,metadata_name)
metadadata_in=open(path_meta_in,'r')

for line in metadadata_in:
	line_out=line.replace(".flac\t",".wav\t")
	metadadata_out.write(line_out)
#ENDFOR

metadadata_in.close()
metadadata_out.close()

########################################################################

