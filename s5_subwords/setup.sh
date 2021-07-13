#!/usr/bin/env bash

. path.sh

if [ ! -d utils ]; then
    echo Setting up symlinks
    ln -s $KALDI_ROOT/egs/wsj/s5/utils utils
fi

if [ ! -d steps ]; then
    echo Setting up symlinks
    ln -s $KALDI_ROOT/egs/wsj/s5/steps steps
fi

echo "Setup done"
