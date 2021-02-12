# Subword recipe for Icelandic

This is a subword-based recipe for Icelandic ASR, modified from the gale-arabic subword implementation recipe for Arabic, which implements BPE. You can find the original subword gale-arabic implementation under egs/gale-arabic/s5c.

We use the Málrómur speech data [1] for training the models. Please find instructions on preparing the speech data below. Instead of implementing the subword algorithms from scratch, as is done with BPE in the s5c gale-arabic recipe, we provide pre-processed Icelandic training data (Málrómur transcripts) for three different subword segmentation methods: BPE, Kvistur, and Unigram (SentencePiece). Please refer to the [technical report](https://github.com/svanhviti16/subword-asr-icelandic/blob/master/s5/Subword_modelling_ASR_summer_2020.pdf) for details.

## Kaldi and basic setup

The system uses the Kaldi speech recognition toolkit. Find download and installing instructions in Kaldi's online documentation:
http://www.danielpovey.com/kaldi-docs/install.html or https://github.com/kaldi-asr/kaldi. We are using a version of Kaldi from February 2017.
A thorough documentation of Kaldi can be found at http://kaldi-asr.org/, for a step-by-step tutorial for beginners see http://kaldi-asr.org/doc/kaldi_for_dummies.html.

*Note:* Per default Kaldi will be installed creating debuggable binaries at the cost of speed. When optimizing for speed you should edit `kaldi/src/kaldi.mk` as described
in http://kaldi-asr.org/doc/build_setup.html.

Kaldi has an excellent collection of examples in it's `$KALDI_ROOT/egs/` directory, have a look at `egs/wsj/` for example.

When you have installed Kaldi and cloned this project, edit `path.sh` and `setup.sh` according to the location of your Kaldi installation.
Run `setup.sh` from your `s5` directory to create symlinks to the folders `steps` and `utils` from an example project. 

Now you should be all set up for experimenting with Kaldi, below are descriptions on both how to use existing models and how to train your own.

## Icelandic speech data

On http://malfong.is/ you can find the Málrómur data used for training these models. Please download this data, and only use the utterances marked as 'correct'.

The run.sh script calls the script `local/malromur_prep_data.sh`, which prepares data in the format of _Málrómur_, i.e. a directory containing a folder `wav` with all the `.wav` files and a text file called `wav_info.txt`, where each line describes one utterance in 11 columns :


	<wav-filename>	<recording-info>	<recording-info>	<gender>	<age>	<prompt (spoken text)>	<utterance length>	vorbis	16000	1	Vorbis


The `malromur_prep_data.sh` script divides the generated data:
 
	local/malromur_prep_data.sh <path-to-audio-files> wav_info.txt data/all
	utils/subset_data_dir_tr_cv.sh --cv-utt-percent 10 data/{all,training_data,test_data}

The prepared data is now in `data/all` and after the subset command the prepared files are divided such that 10% of the data in `data/all` is now in `data/test_data` and the rest in `data/training_data`.

Further information on the Málrómur data preparation can be found in the [ice-kaldi recipe README file](https://github.com/cadia-lvl/ice-asr/tree/master/ice-kaldi/s5).

### Subword data

The folder `subword_ice` holds data preprocessed for training subword ASR models. This is the training/test data from the Málrómur data, and grapheme-as-phoneme based subword lexicons.

The three subword methods available are BPE (byte-pair encoding), Kvistur, and the Unigram subword segmentation algorithm available in the SentencePiece library.

Some preprocessing scripts used to prepare the subword data are also available in this folder, under `utils`.

## Running the scripts
The run.sh script takes care of the training process. Three subword segmentation methods can be provided as command line argument with the run.sh script. 

`./run.sh bpe` or
`./run.sh kvistur` or
`./run.sh unigram`

If no argument is given, the BPE algorithm is applied by default. The model training architecture is described in [2].
The last training step of the script (neural network training) might fail for some reasons; we have not used this step in our experiments.

[1] "Málrómur: A manually verified corpus of recorded Icelandic speech", S. Steingrímsson, S. Helgadóttir, E. Rögnvaldsson, J. Guðnason. NODALIDA 2017.
[2] "A Complete Kaldi Recipe For Building Arabic Speech Recognition Systems", A. Ali, Y. Zhang, P. Cardinal, N. Dahak, S. Vogel, J. Glass. SLT 2014. 
