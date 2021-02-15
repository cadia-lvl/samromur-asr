# Subword recipe for Icelandic

This is a subword-based recipe for Icelandic ASR, modified from the gale-arabic subword implementation recipe for Arabic, which implements BPE. You can find the original subword gale-arabic implementation under egs/gale-arabic/s5c.

We use the Málrómur speech data [1] for training the models. Please find instructions on preparing the speech data below. Please refer to the [technical report](https://github.com/svanhviti16/subword-asr-icelandic/blob/master/s5/Subword_modelling_ASR_summer_2020.pdf) for details.

### Acustic data
To do... 


### Subword methods
We provide scripts for three subwords methods. We modified gthe ale-arbic Byte Pair endcoding recipe in the Kaldi repository for one of the BPE implementations and used Google’s SentencePiece (SP) library for the other BPE implementation (SP_BPE) and the Unigram algorithm. We also have the package Morfessor. 

```
local
└── sw_methods
	├──bpe
	├──sp
	└──morfessor
```

### Dependacies (other than Kaldi)
For Kaldi installtion help refer to ../documentation/setup_kaldi.md

* Python 3.x

We need Google’s [SentencePiece package](https://github.com/google/sentencepiece) to run train subword tokneizer found in sw_methods/sp. 
```
pip3 install sentencepiece
```

## Running the scripts
The run.sh script takes care of the training process. Three subword segmentation methods can be provided as command line argument with the run.sh script. 

```
./run.sh --method [bpe|sp_bpe|unigram|morfessor] \
		 --lang [Code-to-identify-your-run]
``` 

[1] "Málrómur: A manually verified corpus of recorded Icelandic speech", S. Steingrímsson, S. Helgadóttir, E. Rögnvaldsson, J. Guðnason. NODALIDA 2017.

[2] "A Complete Kaldi Recipe For Building Arabic Speech Recognition Systems", A. Ali, Y. Zhang, P. Cardinal, N. Dahak, S. Vogel, J. Glass. SLT 2014. 
