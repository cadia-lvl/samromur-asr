#-*- coding: utf-8 -*- 
#############################################################################################
#create_lexicon.py

#Author   : Carlos Daniel Hernández Mena
#Date     : October 20th, 2021
#Location : Reykjavík University

#Uso:

#	$ python3 local/create_lexicon.py <ruta_al_diccionario_de_pronunciacion>

#Ejemplo de uso concreto:

#	$ python3 local/create_lexicon.py $prondict_orig

#This script creates the following Kaldi files:

#	data/local/dict/lexicon.txt
#	data/local/dict/lexiconp.txt

#Notice: This program is intended for Python 3
#############################################################################################
#Imports

import sys
import re
import os

#############################################################################################

#Output files
archivo_out = open("data/local/dict/lexicon.txt",'w')
archivo_out2= open("data/local/dict/lexiconp.txt",'w')

#Handle the input file
archivo_in = open(sys.argv[1],'r')

#############################################################################################
#Load the input file in a hash table and a python list.

max_len = 0
hash_dic = {}
lista_words = []

for linea in archivo_in:
	linea = linea.replace("\n","")
	linea = re.sub('\s+',' ',linea)
	linea = linea.strip()
	
	lista_linea = linea.split(" ")
	word = lista_linea[0]
	lista_linea.pop(0)
	
	trans = " ".join(lista_linea)
	trans = trans +" "

	hash_dic[word]=trans
	lista_words.append(word)

	longitud = len(word)

	#Verifica si es la palabra mas larga
	if longitud > max_len:
		max_len = longitud
	#ENDIF
#ENDFOR

#Add the symbol <UNK>
lista_words.append("<UNK>")
hash_dic["<UNK>"]="sil"

#Sort the list
lista_words.sort()

#############################################################################################
#Print the dictionaries in the desired format.
for word in lista_words:
	num_espacios = max_len - len(word)

	linea_lex = word +"\t"+hash_dic[word]+"\n"
	archivo_out.write(linea_lex)

	linea_lexp = word + " "*num_espacios+" 1.0\t"+hash_dic[word]+"\n"
	archivo_out2.write(linea_lexp)
#ENDFOR

#############################################################################################
archivo_in.close()
archivo_out.close()
archivo_out2.close()

