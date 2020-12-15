# Defining Kaldi root directory
export KALDI_ROOT=$HOME/kaldi

[ -f $KALDI_ROOT/tools/env.sh ] && . $KALDI_ROOT/tools/env.sh
export PATH=utils/:$KALDI_ROOT/tools/openfst/bin:/opt/mitlm/bin:/opt/sequitur/bin:/opt/kenlm/build/bin:$PWD:$PATH
[ ! -f $KALDI_ROOT/tools/config/common_path.sh ] && echo >&2 "The standard file $KALDI_ROOT/tools/config/common_path.sh is not present -> Exit!" && exit 1
. $KALDI_ROOT/tools/config/common_path.sh

# Activate all althingi specific paths as well as exp, data and mfcc on scratch
. ./conf/path.conf