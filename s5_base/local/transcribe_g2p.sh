#!/bin/bash
#
# Copyright: 2015 Róbert Kjaran
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#
# Train a grapheme-to-phoneme model using Sequitur[1].
#
# [1] M. Bisani and H. Ney, “Joint-sequence models for
#     grapheme-to-phoneme conversion,” Speech Commun., vol. 50, no. 5,
#     pp. 434–451, May 2008.

#. ./path.sh

stage=0
iters=7

. "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/../utils/parse_options.sh

if [ $# -ne 2 ]; then
    cat <<EOF >&2
Usage: $0 <model-dir> <wordlist>
Example: $0 data/local/g2p words.txt > transcribed_words.txt

Transcribe a list of words using g2p model in <model>.
EOF
    exit 1
fi

#model_dir=$1 ; shift
model=$1; shift
wordlist=$1     ; shift
#model=$model_dir/g2p.mdl

g2p.py --apply $wordlist --model $model --encoding="UTF-8"

exit 0
