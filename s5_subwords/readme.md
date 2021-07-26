# Subword recipe for Icelandic
This is a subword-based recipe for an Icelandic ASR built using the Kaldi toolkit. Running the recipe on other languages only requires modifications to the dataset-specific data preparation steps. Subword-based ASR models have the advantage of being able to transcribe out-of-vocabulary words. 

## Running the recipe 
In the folder "run" are the scripts used to interface the recipe. The acoustic and subword modelling are in separate scripts. Most of the subword related modifications affect the lexicon and language model, except that the acoustic model uses graphemes instead of phoenemes for the phonetic units.

### run/run_am.sh
Start by running the script "run/run_am.sh", it has all the steps related to the acoustic model training. It creates a standard LDA+MLLT+SAT system followed by a TDNN model, with i-vectors and speed perturbation. The script is a standard Kaldi recipe except for the creation of the dictionary as it uses the text corpus to create a grapheme based lexicon instead of a phoneme based model. The "lang" and "dict" used for the acoustic model training are prefixed with "base" to distinguish them from their subword counterparts, which will be created later. The "lang" and "dict" are derived from the text corpus, so no g2p translation is required. Note that the text corpus must be normalized; one sentence per line, all characters should be lower or upper case, and all non-character related signs like numbers or punctuations should be removed. 

### Subword model
The subword realted steps are in run/run_sw.sh. There are scripts for three subword tokenizers:
 * [Unigram](https://arxiv.org/abs/1804.10959) 
 * [Byte Pair Encoding](https://arxiv.org/abs/1508.07909)
 * [Morfessor](https://morfessor.readthedocs.io/en/latest/)
 
Please read about the tokenizer in their respective repositories, they all perform the same task, but the WER results will differ for each method. The default tokenizer is a "bpe", all scripts for that tokenizer are provided with this repository. To run the tokenizers "unigram" and the "sp_bpe" [Google's Sentence Piece](https://github.com/google/sentencepiece) is needed, a code snippet for a python virtual environment is provided along with a requirments.txt file. 

For each subword tokenization method, there are two parameters, vocabulary size and boundary marking style. The vocabulary size is a parameter that controls how aggressively the words are tokenized, lower values mean fewer and smaller subword units and vice-versa for higher values. The boundary marking styles are the following (the sentence "dog walks" is used as an example): 
* right-marked (r):  do+ g w+ alk+ s
* left-marked (l):  do +g w +alk +s
* left-right-marked (lr): do+ +g w+ +alk+ +s (The default) 
* word-boundary (wb): do g + w alk s 

The token used to mark the subword boundary can be any sign given that it's not a part of the language, in this setup the default is "+".

### run/run_sw.sh
The first step in the script is to train the subword tokenization model. Depending on its size, the text corpus or a subset of it is used for that. We have been using 4 million lines of text which should be more than enough. When the tokenizer is trained that model is used to tokenize the entire corpus. This subword tokenized text corpus will be used to prepare the Language model. There are three different subword tokenizers in the script Unigram, 

The next step is to create the dictionary folder which that has the lexicon and other files that Kaldi needs. They are all made by extracting information from the subword tokenized text corpus. 

The next step is to prepare the "lang" directory. For that, an external package is needed, which was developed by [Aalto University](https://github.com/aalto-speech/subword-kaldi.git). It is used to create the L.fst for the boundary marking style. Please read their paper, found in the repository, for more information. 

The last step before decoding is to create the language model. The n-gram count has to be higher than in traditional language models. The default is 6-gram for the decoding LM and 8-gram for the rescoring LM.

### run/tdnn_decode.sh
This step is the final step in "run/run_sw.sh". In this step, the decoding graph is compiled. Next, the correct "wer_output_filter" is created depending on the boundary marking style used. This filter is a set of sed commands that will remove the space and boundary marker between individual subword units. Finally the decoding is done for the decoding and rescoring LM.

# Authors
David Erik Mollberg - <david.e.mollberg@gmail.com>


Based on work by Svanhvít Lilja Ingólfsdóttir, Bjarni Barkarson and Steinunn Rut Friðriksdóttir.

# Further reading
[The use of subwords for Automatic Speech Recognition](https://skemman.is/handle/1946/39412) by David Erik Mollberg.

[Technical report on Subword Language Modeling for Icelandic ASR](https://github.com/svanhvitlilja/subword-asr-icelandic/blob/master/s5/Subword_modelling_ASR_summer_2020.pdf) by Svanhvít Lilja Ingólfsdóttir, Bjarni Barkarson and Steinunn Rut Friðriksdóttir.

## Acknowledgements
This project was funded by the Language Technology Programme for Icelandic 2019-2023. The programme, which is managed and coordinated by [Almannarómur](https://almannaromur.is/), is funded by the Icelandic Ministry of Education, Science and Culture.
