Work in progress


# Subword recipe for Icelandic
This is a subword-based recipe for an Icelandic ASR. Running the recipe on other languages only requires modifications to the dataset-specific data preparation steps. Subword-based ASR models have the advantage of being able to create OOV words. 

## Running the recipe 
In the folder "run" are all the scripts needed to run the recipe. The acoustic and subword modelling are in separate scripts. The subword related modifications are only done to the lexicon and language model except that the phonetic units that the acoustic model creates are graphemes instead of phonemes. 

Start by running the script "run_am.sh", it has all the steps related to the acoustic model training. It creates a LDA+MLLT+SAT system and then a TDNN model, with i-vectors and speed perturbation. The script is quite standard except for the creation of the dictionary as it uses the text corpus to create a grapheme based word-level lexicon. The word-level parts e.g. the "lang" and "dict" are called "base". Note that the text corpus must be normalized. That means one sentence per line, making all characters lower or upper case and removing all non-character related signs like numbers or punctuations. 

# License

# Authors
David Erik Mollberg <david.e.mollberg@gmail.com>
Svanhvít Ingólfsdóttir

## Acknowledgements
This project was funded by the Language Technology Programme for Icelandic 2019-2023. The programme, which is managed and coordinated by [Almannarómur](https://almannaromur.is/), is funded by the Icelandic Ministry of Education, Science and Culture.
