# Defining Kaldi root directory
export KALDI_ROOT=/home/dem/kaldi

# Defining The Icelandic Pronunciation directory (modify it for your installation directory!)
#export ICELANDIC_PRONDICT=/media/dem/pumba/Gogn/prondict_sr/frambordabok_asr_v1.txt
export ICELANDIC_PRONDICT=/home/dem/final_project/samromur-asr/local_files/lexicon_samromur/lexicon.txt
# Defining Samrómur Data directory (modify it for your installation directory!)
# Examples dataset (switch to the actual dataset when the dataset is available)
export SAMROMUR_AUDIO=/media/dem/pumba/samromur_v1/audio
export SAMROMUR_META=/home/dem/final_project/samromur-asr/local_files/metadata.tsv

# Path to corpus which is used to create the Language model (G.fst).
export CORPUS=/home/dem/final_project/samromur-asr/local_files/corpus/corpus.txt

export PATH=$KALDI_ROOT/src/ivectorbin:$PWD/utils/:$KALDI_ROOT/src/bin:$KALDI_ROOT/src/online2bin:$KALDI_ROOT/src/onlinebin:$KALDI_ROOT/tools/openfst/bin:$KALDI_ROOT/src/fstbin/:$KALDI_ROOT/src/gmmbin/:$KALDI_ROOT/src/featbin/:$KALDI_ROOT/src/lm/:$KALDI_ROOT/src/lmbin/:$KALDI_ROOT/src/sgmmbin/:$KALDI_ROOT/src/sgmm2bin/:$KALDI_ROOT/src/fgmmbin/:$KALDI_ROOT/src/latbin/:$KALDI_ROOT/src/nnet3bin::$KALDI_ROOT/src/nnetbin:$KALDI_ROOT/src/nnet2bin/:$KALDI_ROOT/src/kwsbin:$PWD:$PATH
