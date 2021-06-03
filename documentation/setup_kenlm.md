# Setup KenLM Language Model Toolkit

This setup guide is tailored for setup on Terra (the compute cluster in LVL).
Feel free to look at the following guide if you want another step by step guide
to setup KenLM: <https://kheafield.com/code/kenlm/>

## Download, Extract and Build Source Code

```console
(kaldi-env) USER@terra:~$ wget -O - https://kheafield.com/code/kenlm.tar.gz |tar xz
(kaldi-env) USER@terra:~$ mkdir kenlm/build
(kaldi-env) USER@terra:~$ cd kenlm/build
(kaldi-env) USER@terra:~/kenlm/build$ cmake ..
(kaldi-env) USER@terra:~/kenlm/build$ make -j2
```

## Update System PATH

```console
(kaldi-env) USER@terra:~/kenlm/build$export PATH="$PWD/bin:$PATH"
```