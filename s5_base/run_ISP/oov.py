#!/usr/bin/env python3


import sys 


text_file=sys.argv[1]
words_file=sys.argv[2]
outfile_file=sys.argv[3]



# Let's open and load content into sets
actual_vocab:set= set()
test_vocab:set = set()
actual_vocab_count:int = 0
with open(text_file) as text, open(words_file) as words:
    for line in text:
        for w in line.split(' ')[1:]:
            test_vocab.add(w.rstrip())
    for line in words: 
        t,_ = line.split(' ')
        actual_vocab.add(t.rstrip())
        actual_vocab_count+=1

# Let's find the words that are in test_vocab but not in actual_vocab
oovs = list(test_vocab.difference(actual_vocab))
count_oovs=len(oovs)
print(f"In the file:{text_file}\nthere are {count_oovs} or a {count_oovs/actual_vocab_count}% oovs rate\n")

# Let's write the oovs to the ouput file
with open(outfile_file, 'w') as oov:
    for line in oovs: 
        oov.write(line+'\n')



