# Defining Kaldi root directory
export KALDI_ROOT=$HOME/kaldi

# Defining The Icelandic Pronunciation directory (modify it for your installation directory!)
export ICELANDIC_PRONDICT_ROOT=$HOME/prondict_sr

# Defining Samrómur Data directory (modify it for your installation directory!)
# Examples dataset (switch to the actual dataset when the dataset is available)
export SAMROMUR_ROOT=$HOME/samromur_recordings_1000
# export SAMROMUR_ROOT=$HOME/samromur

export PATH=$KALDI_ROOT/src/ivectorbin:$PWD/utils/:$KALDI_ROOT/src/bin:$KALDI_ROOT/src/online2bin:$KALDI_ROOT/src/onlinebin:$KALDI_ROOT/tools/openfst/bin:$KALDI_ROOT/src/fstbin/:$KALDI_ROOT/src/gmmbin/:$KALDI_ROOT/src/featbin/:$KALDI_ROOT/src/lm/:$KALDI_ROOT/src/lmbin/:$KALDI_ROOT/src/sgmmbin/:$KALDI_ROOT/src/sgmm2bin/:$KALDI_ROOT/src/fgmmbin/:$KALDI_ROOT/src/latbin/:$KALDI_ROOT/src/nnet3bin::$KALDI_ROOT/src/nnetbin:$KALDI_ROOT/src/nnet2bin/:$KALDI_ROOT/src/kwsbin:$PWD:$PATH
