import sys

segmented_file = sys.argv[1]
corpus = sys.argv[2]
output = sys.argv[3]

segments:dict = {}
with open(segmented_file) as f_in:
    for line in f_in:
        line = line.rstrip()
        if "@@" in line:
            word = line.replace('@@ ', '')
            segments[word] = line

with open(corpus) as f_in:
    with open(output, 'w') as f_out:
        for line in f_in:
            for word in line.split(' '):
                word = word.rstrip()
                if word in segments.keys():
                    f_out.write(segments[word] + ' ')
                else:
                    f_out.write(word + ' ')
            f_out.write('\n')



