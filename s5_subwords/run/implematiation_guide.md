



# 1 Get the script

Run 
```
git clone something with the right branch
```

Please read the general readme files found in samromur-asr/readme and samromur-asr/s5_subwords/readme. The scripts are located in samromur-asr/s5_subword/run/ and samromur-asr/s5_base/run/. The distinction that is made between base and subword is firstly the obious fact that one useses a subword LM and the other a standard word-level model. To allow use to use a subword LM we use a grapheme based Acoustic model (AM) this is in contrast to the standard (base) phoneme AM. That means that we have to train two seperate AM to run the experiment. I have modified the general "run" scripts to fit that purpose. The following is an implematiation guide for this specific experiment. 

The scripts are intented to be run in the following order:
    samromur-asr/s5_subword/run/01_run_am.sh
    samromur-asr/s5_base/run/01_run_am.sh


# 2 Prepare your data. 

Prepare the data in the Kaldi format, this is ofcourse specific to your dataset/s. For Icelandic I used three dataset and compined them into one folder called "combined". I recomend using the same folder structor and namining convention where we make a distiction between the grapheme and phoneme related parts but we try to reuse as much as possible to save space and computation. Have a look through the first steps in samromur-asr/s5_subword/run/01_run_am.sh and use that as a template, you need to change "language" and "root_data_dir" found at the top of the script to localize. The mfcc features only need to be extracted once for both models and will therefore be located in "exp_grapheme/mfcc"

.
├── isl
│   ├── data
│   │   ├── althingi
│   │   └── combined
│	│	│   ├── train
│	│	│	│   ├── cmvn.scp
│	│	│	│   ├── feats.scp
│	│	│	│   ├── frame_shift
│	│	│	│   ├── log
│	│	│	│   ├── q
│	│	│	│   ├── reco2dur
│	│	│	│   ├── segments
│	│	│	│   ├── spk2gender
│	│	│	│   ├── spk2utt
│	│	│	│   ├── split30
│	│	│	│   ├── split50
│	│	│	│   ├── text
│	│	│	│   ├── train.10000K
│	│	│	│   ├── utt2dur
│	│	│	│   ├── utt2num_frames
│	│	│	│   ├── utt2spk
│	│	│	│   └── wav.scp
│	│	│   ├── train_sp
│	│	│   ├── train_sp_40000k_hires
│	│	│   └── train_sp_hires
│   │   ├── dict_grapheme
│   │   ├── dict_phoneme
│   │   ├── lang_grapheme
│   │   ├── lang_phoneme
│   │   ├── local_grapheme
│   │   ├── local_phoneme
│   │   ├── malromur
│   │   └── samromur
│   ├── exp_grapheme
│   │   ├── chain
│   │   ├── mfcc
│   │   ├── mono
│   │   ├── mono_ali
│   │   ├── nnet3
│   │   ├── tri1
│   │   ├── tri1_ali
│   │   ├── tri2b
│   │   ├── tri2b_ali
│   │   ├── tri3b
│   │   ├── tri3b_ali_train_sp
│   │   └── tri3b_lats_sp
│   ├── exp_phoneme
│   │   ├── ...
│   │   ...        
│   └── text_corpora
│       ├── logs
│       ├── rmh_2020-11-23
│       └── rmh_2020-11-23+sm+malromur+althingi_sorted_cleaned
└── spanish
    ├── speech
    │   ├── Test
    │   └── Train
    └── text
        └── TEXTO_CORPUMATIC


## 3 Train the acoustic models (01_run_am.sh, 02_run_tdnn.sh and run_ivector_common.sh)
Run the script s5_subword/01_run_am.sh with  

We will create two models that will be located in exp_phoneme and exp_grapheme. The script "01_run_am.sh" has all the prelimitary steps (GMM-HMM) needed before creating the tdnn model in "02_run_tdnn.sh". That script can be called from the final step in "01_run_am.sh" Training the TDNN requires a GPU, or a few, plus a considerable amount of disc space to store all the examples generated. We use both volume and speed pertubation (sp) on the data. I haven't been able to find a way to reuse the exmaples (called egs) for both models, mostlikey because the tragets are grapheme or phoneme. In our case the isl-egs where 2x64gb, they will be automatically deleted once the training is done. 

* The text in the train, dev and test should be added to the text corpus before running step 2 in "01_run_am.sh". There are further notes in 01_run_am.sh related to this that might be of use.

Before training the tdnn model we need an Ivector feature extractor and to do the data augmentation. "02_run_tdnn.sh" calls "local/nnet3/run_ivector_common.sh". The steps 1 and 3-8 can be done once for both models. The paths in s5_base/run/02_run_tdnn.sh expect that these steps have been done in s5_subword/run/02_run_tdnn.sh. Step 2, generating alignments the alignments for the augmentated data, has to be done for both models and so do steps 9-13.  



# 4 Sanity check

At this point I recommend making a small subset (1m lines or less) of the text corpus to quickly train an LM and test decoding with the models. The steps for the subword models are in "s5_subwords/03_run_sw.sh, we will use the defualt configurations, please read samromur-asr/s5_subwords/readme for further explenation. 

To localize "03_run_sw.sh" change the paths for "root_data_dir", "language" and "text_corpus". Make sure you have the KenLM-toolkit installed we use the tool "lmplz" to generate the LM

