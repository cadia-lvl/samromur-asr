#-*- coding: utf-8 -*- 
########################################################################
#fix_text.py

#Autor: Carlos Daniel Hernández Mena
#Fecha: 19 de Abril de 2021
#Lugar: Universidad de Reikiavik

#Uso:

#	$ python3 fix_text.py <directory_in_data>

#Ejemplo de uso concreto:

#	$ python3 fix_text.py data/train

#	$ python3 fix_text.py data/dev

#	$ python3 fix_text.py data/eval

#This scripts recieves a transcription file and removes the extra spaces.

#Nota: Este programa está pensado para Python 3
#Nota: Si el archivo de salida ya existía, este programa lo sobre-escribe
########################################################################
#Importar módulos necesarios

#Módulo para funciones del sistema operativo
import sys

#Módulo para manejar expresiones regulares
import re

#Módulo para manejar funciones del sistema operativo
import os

#Módulo para hacer operaciones con archivos y carpetas
import shutil

########################################################################
#Getting input parameters
data_portion=sys.argv[1]
text_file=os.path.join(data_portion,"text")
text_temp = os.path.join(data_portion,"text_temp")
########################################################################

#Change the name of the text file to be fixed.
shutil.move(text_file, text_temp)

########################################################################
#Read the text file line per line

#Open files
archivo_text_temp=open(text_temp,'r')
archivo_text_out = open(text_file,'w')

for linea in archivo_text_temp:
	linea=linea.replace('\n','')
	linea=re.sub('\s+',' ',linea)
	linea=linea.strip()
	archivo_text_out.write(linea+'\n')
#ENDFOR

#Close files
archivo_text_temp.close()
archivo_text_out.close()

#Remove the temporary text file
os.remove(text_temp)

########################################################################

