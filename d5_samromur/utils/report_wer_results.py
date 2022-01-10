#-*- coding: utf-8 -*- 
########################################################################
#report_wer_results.py

#Author   : Carlos Daniel Hernández Mena
#Date     : January 1st, 2021
#Location : Reykjavík University

#Usage:

#	$ python3 report_wer_results.py <experiment_dir>

#Example:

#	$ python3 report_wer_results.py exp/

#Description:

#This script finds all the WER results found in the exp/ folder
#and put them in a file called RESULTS.

#Notice: This program is intended for Python 3
########################################################################
#Imports

import sys
import os
import re

########################################################################
#Important variables

EXP_DIR=sys.argv[1]

########################################################################
#Create the output file

if not os.path.exists("RESULTS"):
	file_out = open("RESULTS",'w')
	#Print a header
	file_out.write("WER and CER results are reported in a range between 0 and 1.\n")
else:
	file_out = open("RESULTS",'a')
#ENDIF

patern=r'Test on.*?'
for root, dirs, files in os.walk(EXP_DIR):
	for filename in files:
		if filename == "wer_report":
			path_to_wer_file=os.path.join(root,filename)
			wer_file=open(path_to_wer_file,'r')			
			#Find the overall WER Result in te current file
			for line in wer_file:
				find_pattern=re.match(patern,line)
				if find_pattern!=None:
					file_out.write(line)
				#ENDIF
			#ENDFOR
			wer_file.close()
		#ENDIF
#ENDFOR

#Close the open files.
file_out.close()

########################################################################

