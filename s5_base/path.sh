#!/usr/bin/env bash
module load kenlm
module load cuda/10.2

# Defining Kaldi root directory
export KALDI_ROOT=${KALDI_ROOT:-/data/tools/kaldi-git/2020-03-06}
[ -f $KALDI_ROOT/tools/env.sh ] && . $KALDI_ROOT/tools/env.sh
export PATH=$PWD/utils/:$KALDI_ROOT/tools/openfst/bin:/opt/mitlm/bin:$KALDI_ROOT/tools/sequitur-g2p/bin:$PWD:$PATH
[ ! -f $KALDI_ROOT/tools/config/common_path.sh ] && echo >&2 "The standard file $KALDI_ROOT/tools/config/common_path.sh is not present -> Exit!" && exit 1
. $KALDI_ROOT/tools/config/common_path.sh
