#!/usr/bin/env python3

import sentencepiece as spm
import time
import argparse

def boolean_string(s):
    if s not in {'False', 'True', 'false', 'true', "1", "0"}:
        raise ValueError('Not a valid boolean string')
    return s == 'True' or s=='true' or s=="1"

def model_check(s):
    s = s.lower()
    if s not in {'unigram', 'bpe', 'sp_bpe'}:
        raise ValueError('Nota valid input, should be unigram/bpe')
    if s == 'sp_bpe':
        s = 'bpe'
    return s

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Create BPE/Unigram tokization model using the SentencePiece package')
    parser.add_argument('-i', '--training_corpus', required=True, help='Path to the text LM corpus')
    parser.add_argument('-o', '--output', required=True, help='Output location, most likely data/lang/training')
    parser.add_argument('-v', '--vocab_size', required=False, default='1000', help='Number of subword units to create')
    parser.add_argument('-l', '--larger_corpus', required=False, default=False, type=boolean_string, help='Parameter needed to be true when tranining on a very larger corpus, \
                                            has performance downsides if always true when not need. Should only be used with Unigram')
    parser.add_argument('-t', '--type', required=False, type=model_check, help='In the SentencePiece library we can train either a Unigram or BPE model')
    args = parser.parse_args()

    t0 = time.time()

    model=args.type

    print(f'Training a {model} model')

    # vocab_size - type: int32 default: 8000
    # model_type - unigram, char, word, bpe
    # normalization_rule_name - (Normalization rule name. Choose from nfkc or identity) identity means no normalization
    # train_extremely_large_corpus - Increase bit depth for unigram tokenization.) 
    # all flags are here https://github.com/google/sentencepiece/blob/master/doc/options.md
    # Colab demo here https://colab.research.google.com/github/google/sentencepiece/blob/master/python/sentencepiece_python_module_example.ipynb#scrollTo=Lf5Fs_pPIKif
    # max_sentencepiece_length (maximum length of sentence piece)  type: int32 default: 16
    #--input_sentence_size: The number of lines spm_train first loads. Remaining lines are simply discarded. Since spm_train loads entire corpus into memory, this size will depend on the memory size of the machine. It also affects training time.
    #--training_sentence_size: The number of lines to train BPE/unigram model.
    #--mining_sentence_size: The number of lines to generate seed pieces. spm_train extracts frequent substring from the corpus with suffix array, which requires O(10N) memory space. This setting is valid when --model_type=unigram.
    #--seed_sentencepiece_size: The size of seed pieces. This setting is valid when --model_type=unigram.


    spm.SentencePieceTrainer.train(input=args.training_corpus, \
                                model_prefix=args.output, \
                                vocab_size=args.vocab_size, \
                                model_type=model, \
                                input_sentence_size = 4000000, \
                                normalization_rule_name='identity', \
                                max_sentencepiece_length=32, \
                                train_extremely_large_corpus=args.larger_corpus) #Increase bit depth for unigram tokenization
    t1 = time.time()
    print(f"Training a {model} model {t1-t0} sek")