# Setup Samromur-ASR

## Setup Kaldi

Make sure you have installed Kaldi. If not, please follow this guide:
* [Setup Guide for Kaldi-ASR](/setup_kaldi.md)


<!-- TODO: How to get samromur data fram Clarin and set enviroment varialbes -->
<!-- ## Get data -->

## Navigate to s5

Make sure you are in the right directory.

```console
(kaldi-env) USER@terra:~/kaldi/egs/samromur-asr/$ cd s5/
```

## Configure the run.sh script

Open `s5/run.sh` in your favorite text editor and configure these hyperparameters.

```php
stage=0
num_threads=4
num_jobs=16
minibatch_size=128
```
g
Make sure the variables are assigned to the correct directory. 

<details>
<summary>Exmple data set (1000 samples)</summary>

```php
samromur_audio_dir=~/samromur_recordings_1000/audio
samromur_meta_file=~/samromur_recordings_1000/metadata.tsv
```
</details>

<details>
<summary>Entire data set</summary>

```php
samromur_audio_dir=~/samromur_recordings/audio
samromur_meta_file=~/samromur_recordings/metadata.tsv
```
</details>

## Make sure the scripts are executable

```console
(kaldi-env) USER@terra:~/kaldi/egs/samromur-asr/s5$ chmod +x *.sh
```

## Excute run.sh
```console
(kaldi-env) USER@terra:~/kaldi/egs/samromur-asr/s5$ ./run.sh 
```

Now you should have successfully:
* created an acoustic model
* trained your language model

## Clean directory

To clear all generated data 
```console
(kaldi-env) USER@terra:~/kaldi/egs/samromur-asr/s5$ ./clean.sh
```