<h1 align="center">
Creating an Accoustic Model from the Samrómur Corpus
</h1>

<!-- omit in toc -->
## Introduction

One of the first steps in creating the Samromur ASR is to create a Accoustic Model (AM) from the audio files.

The task involvs creating meta data files for the `Audio data` and the `Language data`. 

These files will map each audio file to a speacker, gender, age, and the context of the files.


## Data Preperation

To train an acoustic model you need speech data in the form of audio files paired with text.

This data needs to be prepared in a certain way to be processable by Kaldi. The script `local/prep_data.sh` prepares data in the format of _Málrómur_, i.e. a directory containing a folder `wav` with all the `.wav` files and a text file called `wav_info.txt`, where each line describes one utterance in 11 columns :


## spk2gender
This file informs about speakers gender. As we assumed, 'speakerID' is a unique name of each speaker (in this case it is also a 'recordingID' - every speaker has only one audio data folder from one recording session). In my example there are 5 female and 5 male speakers (f = female, m = male).

Pattern: <speakerID> <gender>

cristine f
dad m
josh m
july f
...

## wav.scp
This file connects every utterance (sentence said by one person during particular recording session) with an audio file related to this utterance. If you stick to my naming approach, 'utteranceID' is nothing more than 'speakerID' (speaker's folder name) glued with *.wav file name without '.wav' ending (look for examples below).

Pattern: <uterranceID> <full_path_to_audio_file>

dad_4_4_2 /home/{user}/kaldi/egs/digits/digits_audio/train/dad/4_4_2.wav
july_1_2_5 /home/{user}/kaldi/egs/digits/digits_audio/train/july/1_2_5.wav
july_6_8_3 /home/{user}/kaldi/egs/digits/digits_audio/train/july/6_8_3.wav
...

## text
This file contains every utterance matched with its text transcription.

Pattern: <uterranceID> <text_transcription>

dad_4_4_2 four four two
july_1_2_5 one two five
july_6_8_3 six eight three
...

## utt2spk
This file tells the ASR system which utterance belongs to particular speaker.

Pattern: <uterranceID> <speakerID>

dad_4_4_2 dad
july_1_2_5 july
july_6_8_3 july
...

## corpus.txt


```console
$ ls /data/samromur/
samromur_recodrings_1000.zip
```