import morfessor

io = morfessor.MorfessorIO()

text_corpus="/data/asr/malromur/malromur2017/malromur_corpus.txt"

train_data = list(io.read_corpus_file(text_corpus))

model_types = morfessor.BaselineModel()
model_logtokens = morfessor.BaselineModel()
model_tokens = morfessor.BaselineModel()

model_types.load_data(train_data, count_modifier=lambda x: 1)
def log_func(x):
    return int(round(math.log(x + 1, 2)))
model_logtokens.load_data(train_data, count_modifier=log_func)
model_tokens.load_data(train_data)

models = [model_types, model_logtokens, model_tokens]

for model in models:
    model.train_batch()

goldstd_data = io.read_annotations_file('gold_std')
ev = morfessor.MorfessorEvaluation(goldstd_data)
results = [ev.evaluate_model(m) for m in models]

wsr = morfessor.WilcoxonSignedRank()
r = wsr.significance_test(results)
WilcoxonSignedRank.print_table(r)
"""