#!/usr/bin/env bash

# TODO: load kenlm module or make sure it's in kaldi/tools path
module load kenlm

# Defining Kaldi root directory
export KALDI_ROOT=$HOME/kaldi
#export KALDI_ROOT=${KALDI_ROOT:-`pwd`/../../..}
[ -f $KALDI_ROOT/tools/env.sh ] && . $KALDI_ROOT/tools/env.sh
export PATH=$PWD/utils/:$KALDI_ROOT/tools/openfst/bin:/opt/mitlm/bin:/opt/sequitur/bin:$PWD:$PATH
[ ! -f $KALDI_ROOT/tools/config/common_path.sh ] && echo >&2 "The standard file $KALDI_ROOT/tools/config/common_path.sh is not present -> Exit!" && exit 1
. $KALDI_ROOT/tools/config/common_path.sh

#. ./conf/path.conf