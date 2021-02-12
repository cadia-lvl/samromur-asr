#Kaldi paths
export KALDI_ROOT=/home/derik/work/kaldi
export PATH=$KALDI_ROOT/src/ivectorbin:$PWD/utils/:$KALDI_ROOT/src/bin:$KALDI_ROOT/src/online2bin:$KALDI_ROOT/src/onlinebin:$KALDI_ROOT/tools/openfst/bin:$KALDI_ROOT/src/fstbin/:$KALDI_ROOT/src/gmmbin/:$KALDI_ROOT/src/featbin/:$KALDI_ROOT/src/lm/:$KALDI_ROOT/src/lmbin/:$KALDI_ROOT/src/sgmmbin/:$KALDI_ROOT/src/sgmm2bin/:$KALDI_ROOT/src/fgmmbin/:$KALDI_ROOT/src/latbin/:$KALDI_ROOT/src/nnet3bin::$KALDI_ROOT/src/nnetbin:$KALDI_ROOT/src/chainbin/:$KALDI_ROOT/src/nnet2bin/:/opt/kenlm/build/bin:$KALDI_ROOT/src/kwsbin:$PWD:$PATH


#Paths for SRILM
#export LIBLBFGS=/work/derik/kaldi/tools/liblbfgs-1.10
#export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-}:${LIBLBFGS}/lib/.libs
#export SRILM=/work/derik/kaldi/tools/srilm
#export PATH=${PATH}:${SRILM}/bin:${SRILM}/bin/i686-m64