# Introduction to Kaldi

## What is Kaldi-ASR

<http://kaldi-asr.org/doc/about.html>

## The usual way of using Kaldi

1. Have already existing manual labeled training data for a given language.
2. Train a statistical model of speech. The model will be composed of a language model (LM) and an acoustic model (AM)
3. Given the speech signal (Bayes), the model will assign a probability that a particular sentence is being said (hypothesis).
4. The most probable hypothesis is selectd (MAP rule).

## Resources needed to build an ASR

### Speech corpus

* A collection of speech signals
* Manual transcription of what was being said for each signal (does not have to be aligned*)

### Lexicon (A pronunciation dictionary)

* A list of words that are transcribed to a string of sub-word phonetic units (phonemes).
* Possibly one-to-many mapping

The Pronunciation Dictionary for Icelandic can be accessed here:
[http://malfong.is/?pg=framburdur](http://malfong.is/?pg=framburdur)

`$ kaldi/src/featbin/`
* Focus on folders ending with “bin”
* Simple executable binaries
* Chaining them together will produce an ASR
* Bash will be the glue binding them all together


## Data preparation
## Feature extraction
## GMM
## HMM model training
## Decoding + Evaluation


## Main Files to focus on

    run.sh
    path.sh
    cmd.sh

Focus on:
    ./data
    ./exp
    ./mfcc


## Input Files

`data/lang` contains language specific stuff

* Focus on: `spk2utt`, `text`, `utt2spk`, `wav.scp`

`./data/lang_test_tg` contains language stuff specific for decoding

`./train_yesno` and `./test_yesno` contain training/testing data



## Kaldi table concept

Kaldi stores data on disk as either _scp_ or _ark_

scp - mapping from key to filename or pipe

ark – mapping from key to data

Read more:
[http://kaldi-asr.org/doc/io.html](http://kaldi-asr.org/doc/io.html)


## Feature Extraction

* **MFCC** - Mel frequency cepstral coefficients
* **Cepstrum** - aka. Delta cepstrum: time derivatives of (energy + MFCC) which give velocity and acceleration. Check out: `steps/compute_cmvn_stats.sh`
* dsf
