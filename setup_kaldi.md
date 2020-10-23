# Setup Kaldi-ASR

## Assign Conda package manager to your user shell

```console
USER@terra:~$ source /data/tools/anaconda/etc/profile.d/conda.sh
```

## Create a Conda virtual environment

```console
USER@terra:~$ conda create --name kaldi-env python=2.7
```

## Add Conda to your user bash profile

```console
USER@terra:~$ conda init
```

## Activate your Conda environment

```console
USER@terra:~$ conda activate kaldi-env
```

## Install pip package manager

```console
(kaldi-env) USER@terra:~$ conda install pip
```

## Install Numpy

```console
(kaldi-env) USER@terra:~$ conda install -c anaconda numpy
```

## Download Swig

```console
(kaldi-env) USER@terra:~$ wget -P /home/USER http://prdownloads.sourceforge.net/swig/swig-4.0.0.tar.gz
```

If it doesn't work, manually place the file to your user root directory /home/USER/

## Install Swig

```console
(kaldi-env) USER@terra:~$ chmod 777 swig-4.0.0.tar.gz
(kaldi-env) USER@terra:~$ tar -xzvf swig-4.0.0.tar.gz
(kaldi-env) USER@terra:~$ cd swig-4.0.0
(kaldi-env) USER@terra:~$ ./configure --prefix=/home/USER/swig-4.0.0
(kaldi-env) USER@terra:~$ make
(kaldi-env) USER@terra:~$ make install
(kaldi-env) USER@terra:~$ export SWIG_PATH=/home/USER/swig-4.0.0/bin
(kaldi-env) USER@terra:~$ export PATH=$SWIG_PATH:$PATH
(kaldi-env) USER@terra:~$ source /etc/profile
(kaldi-env) USER@terra:~$ rm swig-4.0.0.tar.gz
```

## Install OpenBlas

```console
(kaldi-env) USER@terra:~/kaldi/tools$ cp  /data/tools/kaldi/tools/OpenBLAS-*.tar.gz .
(kaldi-env) USER@terra:~/kaldi/tools$ tar -xzvf OpenBLAS-*.tar.gz
(kaldi-env) USER@terra:~/kaldi/tools$ rm OpenBLAS-*.tar.gz
(kaldi-env) USER@terra:~/kaldi/tools$ mv xianyi-OpenBLAS-* OpenBLAS
(kaldi-env) USER@terra:~/kaldi/tools$ make PREFIX=$(pwd)/OpenBLAS/install USE_LOCKING=1 USE_THREAD=0 -C OpenBLAS all install
```

## Install Cub

```console
(kaldi-env) USER@terra:~/kaldi/tools$ cp  /data/tools/kaldi/tools/cub-1.8.0.zip .
(kaldi-env) USER@terra:~/kaldi/tools$ unzip -oq cub-1.8.0.zip
(kaldi-env) USER@terra:~/kaldi/tools$ rm -f cub-1.8.0.zip
(kaldi-env) USER@terra:~/kaldi/tools$ ln -s cub-1.8.0/ cub
```

## Switch Directories

```console
(kaldi-env) USER@terra:~/kaldi/tools$ cd ../src/
```

## Set Kaldi Configuration Flags

```console
(kaldi-env) USER@terra:~/kaldi/src$ CXX=g++-7 ./configure --mathlib=OPENBLAS  --cudatk-dir=/usr/local/cuda-10.0
```

## Compile Kaldi

\<NCPU\> = Number of CPU to use. 

If you want to check out the number of available cores on your system run:

```console
(kaldi-env) USER@terra:~/kaldi/src$ nproc
32
```

In our case, Terra has 32 cores available, but  8 cores seem to be sufficient for this task.

## With output file

```console
(kaldi-env) USER@terra:~/kaldi/src$ make -j clean depend 2&> compile_output.txt; make -j <NCPU> &&> compile_output.txt
```

## Without the output file

```console
(kaldi-env) USER@terra:~/kaldi/src$ make -j clean depend; make -j <NCPU>
```

## Get Kaldi

```console
(kaldi-env) USER@terra:~$ git clone https://github.com/kaldi-asr/kaldi.git kaldi --origin upstream
(kaldi-env) USER@terra:~$ ls
kaldi  scratch  swig-4.0.0  work
```

## Install Kaldi
This might not be needed
```console
(kaldi-env) USER@terra:~$ cd ~/kaldi/tools
(kaldi-env) USER@terra:~/kaldi/tools$ make -j 12
(kaldi-env) USER@terra:~/kaldi/tools$ cd ../src/
(kaldi-env) USER@terra:~/kaldi/src$ make -j 12
```

## Verify that build was successful

```console
(kaldi-env) USER@terra:~/kaldi/src$ tail -2 make_output.txt
Done
```

## Test Example Project

```console
(kaldi-env) USER@terra:~/kaldi/src$ cd ../egs/yesno/s5/
(kaldi-env) USER@terra:~/kaldi/egs/yesno/s5$ ./run.sh | tail -1
%WER 0.00 [ 0 / 232, 0 ins, 0 del, 0 sub ] exp/mono0a/decode_test_yesno/wer_10_0.0
```

Feel free to look at the following guide if you want another step by step guide to setup Kaldi:
<http://jrmeyer.github.io/asr/2016/01/26/Installing-Kaldi.html>
