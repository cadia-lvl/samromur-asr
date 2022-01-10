#-*- coding: utf-8 -*- 
########################################################################
#report_wer_results.py

#Author   : Carlos Daniel Hernández Mena
#Date     : December 12nd, 2021
#Location : Reykjavík University

#Usage:

#	$ python3 report_wer_results.py <experiment_dir>

#Example:

#	$ python3 report_wer_results.py exp/

#Description:

#This finds all the WER results found in the exp/folder
#and put them in a file called RESULTS.

#Notice: This program is intended for Python 3
########################################################################
#Imports

import sys
import os

########################################################################
#Important variables

EXP_DIR=sys.argv[1]

########################################################################
#Create the output file

if not os.path.exists("RESULTS"):
	file_out = open("RESULTS",'w')
else:
	file_out = open("RESULTS",'a')
#ENDIF

for root, dirs, files in os.walk(EXP_DIR):
	for filename in files:
		if filename == "best_wer":
			path_to_wer_file=os.path.join(root,filename)
			wer_file=open(path_to_wer_file,'r')
			wer_result=wer_file.read()
			wer_result=wer_result.replace("\n","")
			line_out=root+" "+wer_result
			file_out.write(line_out+"\n")
			wer_file.close()
		#ENDIF
#ENDFOR

#Close the open files.
file_out.close()

########################################################################

