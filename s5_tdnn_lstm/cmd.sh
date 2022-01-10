#!/usr/bin/env bash
# "queue.pl" uses qsub.  The options to it are
# options to qsub.  If you have GridEngine installed,
# change this to a queue you have access to.
# Otherwise, use "run.pl", which will run jobs locally
# (make sure your --num-jobs options are no more than
# the number of cpus on your machine.

# Terra
if [[ $(hostname -f) == terra.hir.is ]]; then

  # run with slurm:

  export train_cmd="utils/slurm.pl"
  export decode_cmd="utils/slurm.pl --mem 8G"
  export mkgraph_cmd="utils/slurm.pl --mem 8G"
  export big_memory_cmd="utils/slurm.pl --mem 16G"
  export cuda_cmd="utils/slurm.pl --gpu 1"
else

  #c) run it locally...
  export train_cmd=utils/run.pl
  export decode_cmd=utils/run.pl
  export cuda_cmd=utils/run.pl
  export mkgraph_cmd=utils/run.pl

fi

