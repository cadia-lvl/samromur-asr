#!/usr/bin/env bash
#--------------------------------------------------------------------#
#Copyright   2022 Reykjavik University 
#Author: Carlos Daniel Hernández Mena - carlosm@ru.is

#--------------------------------------------------------------------#
this_script="run.sh"
echo " "
echo "+++++++++++++++++++++++++++++++++++++++++++++"
echo "INFO ($this_script): Starting the Recipe"
date
echo "+++++++++++++++++++++++++++++++++++++++++++++"
echo " "

#--------------------------------------------------------------------#
# To be run from the SAMROMUR_NEMO directory

echo "-----------------------------------"
echo "Initialization ..."
echo "-----------------------------------"

#--------------------------------------------------------------------#
#Setting up important paths and variables
#--------------------------------------------------------------------#
# NOTE! In the future the ASR data, LM training text and pronunciation 
#dictionary will be downloaded from online first, e.g. Clarin

corpus_root=/home/carlosm/CORPUS/samromur_21.05

arpa_lm=/home/carlosm/VARIOS_PROGRAMAS/SRILM/6GRAM_with_SRILM/6GRAM_ARPA_MODEL.bin

#Destination of the corpus in wav version
corpus_wav_path=/home/carlosm/CORPUS
corpus_wav_name=samromur_21.05_wav

#--------------------------------------------------------------------#
#CONTROL PANEL
#--------------------------------------------------------------------#

#Choosing the GPUs for the training process.
CUDA_DEVICE_ORDER="PCI_BUS_ID"

##Only one GPU
#CUDA_VISIBLE_DEVICES="1"
#num_gpus=1

##Multiple GPUs
#CUDA_VISIBLE_DEVICES="0,4,5"
num_gpus=2

nj_train=2
nj_decode=2
    
from_stage=0
to_stage=7

#--------------------------------------------------------------------#
#Exit immediately in case of error.
set -eo pipefail

#--------------------------------------------------------------------#
#Inform to the user
echo " "
echo "INFO ($this_script): Initialization Done!"
echo " "

#--------------------------------------------------------------------#
#Verifiying that some important files are in place.
#--------------------------------------------------------------------#

[ ! -d "$corpus_root" ] && echo "$0: expected $corpus_root to exist" && exit 1;

[ ! -f "$arpa_lm" ] && echo "$0: expected $arpa_lm to exist" && exit 1;

#--------------------------------------------------------------------#
#Flac to WAV conversion.
#--------------------------------------------------------------------#
current_stage=0
if  [ $current_stage -ge $from_stage ] && [ $current_stage -le $to_stage ]; then
    echo "-----------------------------------"
    echo "Stage $current_stage: Converting from flac to wav"
    echo "-----------------------------------"
    
    python3 local/flac2wav.py $corpus_root $corpus_wav_path $corpus_wav_name
    
    echo " "
    echo "INFO ($this_script): Stage $current_stage Done!"
    echo " "
fi

#--------------------------------------------------------------------#
#Flac to WAV conversion.
#--------------------------------------------------------------------#
current_stage=1
if  [ $current_stage -ge $from_stage ] && [ $current_stage -le $to_stage ]; then
    echo "-----------------------------------"
    echo "Stage $current_stage: Creating ./data directories and manifests"
    echo "-----------------------------------"
    
    python3 local/create_manifests.py $corpus_wav_path/$corpus_wav_name
    
    mkdir -p data/
    
    mkdir -p data/train
    mkdir -p data/test
    mkdir -p data/dev
    
    mv train_manifest.json data/train
    mv test_manifest.json data/test
    mv dev_manifest.json data/dev
    
    echo " "
    echo "INFO ($this_script): Stage $current_stage Done!"
    echo " "
fi

#--------------------------------------------------------------------#
#Do the training
#--------------------------------------------------------------------#
current_stage=2
if  [ $current_stage -ge $from_stage ] && [ $current_stage -le $to_stage ]; then
    echo "-----------------------------------"
    echo "Stage $current_stage: Training Process"
    echo "-----------------------------------"
    
    #Prepare the experiment
    num_epochs=50
    
    exp_name=model_training
    exp_dir=exp/$exp_name
    mkdir -p exp
    mkdir -p exp/$exp_name
    
    cp steps/nemo_training.py $exp_dir

    #Start the training process.
    python3 $exp_dir/nemo_training.py $num_gpus $nj_train $num_epochs $exp_dir \
                                      conf/Config_QuartzNet15x1SEP_Icelandic.yaml \
                                      data/train/train_manifest.json \
                                      data/dev/dev_manifest.json
    
    echo " "
    echo "INFO ($this_script): Stage $current_stage Done!"
    echo " "
fi

#--------------------------------------------------------------------#
#Inference without Language Model
#--------------------------------------------------------------------#
current_stage=3
if  [ $current_stage -ge $from_stage ] && [ $current_stage -le $to_stage ]; then
    echo "-----------------------------------"
    echo "Stage $current_stage: Inference without Language Model"
    echo "-----------------------------------"
    
    #Prepare the experiment for dev
    exp_name=dev_inference_no_lm
    exp_dir=exp/$exp_name
    mkdir -p exp
    mkdir -p exp/$exp_name
    
    cp steps/inference_no_lm.py $exp_dir
    
    #Start the inference process
    python3 $exp_dir/inference_no_lm.py $nj_decode $exp_dir \
                                        conf/Config_QuartzNet15x5_Icelandic.yaml \
                                        data/dev/dev_manifest.json \
                                        exp/model_training

    #----------------------------------------------------------------#
    #Prepare the experiment for test
    exp_name=test_inference_no_lm
    exp_dir=exp/$exp_name
    mkdir -p exp
    mkdir -p exp/$exp_name
    
    cp steps/inference_no_lm.py $exp_dir
    
    #Start the inference process
    python3 $exp_dir/inference_no_lm.py $nj_decode $exp_dir \
                                        conf/Config_QuartzNet15x5_Icelandic.yaml \
                                        data/test/test_manifest.json \
                                        exp/model_training
    
    echo " "
    echo "INFO ($this_script): Stage $current_stage Done!"
    echo " "
fi

#--------------------------------------------------------------------#
#Inference with Language Model
#--------------------------------------------------------------------#
current_stage=4
if  [ $current_stage -ge $from_stage ] && [ $current_stage -le $to_stage ]; then
    echo "-----------------------------------"
    echo "Stage $current_stage: Inference with Language Model"
    echo "-----------------------------------"
    
    #Prepare the experiment
    exp_name=dev_inference_with_lm
    exp_dir=exp/$exp_name
    mkdir -p exp
    mkdir -p exp/$exp_name
    
    cp steps/inference_with_lm.py $exp_dir

    #Start the inference process
    python3 $exp_dir/inference_with_lm.py $nj_decode $exp_dir $arpa_lm \
                                          data/dev/dev_manifest.json \
                                          exp/model_training

    #----------------------------------------------------------------#

    #Prepare the experiment
    exp_name=test_inference_with_lm
    exp_dir=exp/$exp_name
    mkdir -p exp
    mkdir -p exp/$exp_name
    
    cp steps/inference_with_lm.py $exp_dir

    #Start the inference process
    python3 $exp_dir/inference_with_lm.py $nj_decode $exp_dir $arpa_lm \
                                          data/test/test_manifest.json \
                                          exp/model_training   

    echo " "
    echo "INFO ($this_script): Stage $current_stage Done!"
    echo " "
fi

#--------------------------------------------------------------------#
#Report WER Results 
#--------------------------------------------------------------------#
current_stage=5
if  [ $current_stage -ge $from_stage ] && [ $current_stage -le $to_stage ]; then
    echo "-----------------------------"
    echo "Stage $current_stage: Printing the WER Results"
    echo "-----------------------------"
    
    python3 utils/report_wer_results.py exp
    
    echo " "
    echo "INFO ($this_script): Stage $current_stage Done!"
    echo " "
fi

#--------------------------------------------------------------------#
#Example: Transcribe 1 audio with no Language Model
#--------------------------------------------------------------------#
current_stage=6
if  [ $current_stage -ge $from_stage ] && [ $current_stage -le $to_stage ]; then
    echo "-----------------------------"
    echo "Stage $current_stage: Example: Transcribe 1 audio with no Language Model"
    echo "-----------------------------"

    #Prepare the experiment
    nemo_model=utils/example_model.ckpt
    audio_in=utils/example_audio.wav
    
    python3 utils/trans_1_no_lm.py $nemo_model $audio_in
    
    echo " "
    echo "INFO ($this_script): Stage $current_stage Done!"
    echo " "
fi

#--------------------------------------------------------------------#
#Example: Transcribe 1 audio with an ARPA Language Model
#--------------------------------------------------------------------#
current_stage=7
if  [ $current_stage -ge $from_stage ] && [ $current_stage -le $to_stage ]; then
    echo "-----------------------------"
    echo "Stage $current_stage: Example: Transcribe 1 audio with an ARPA Language Model"
    echo "-----------------------------"

    #Prepare the experiment
    nemo_model=utils/example_model.ckpt
    arpa_lang_model=utils/example_lm.arpa
    audio_in=utils/example_audio.wav
    
    python3 utils/trans_1_with_lm.py $nemo_model $arpa_lang_model $audio_in
    
    echo " "
    echo "INFO ($this_script): Stage $current_stage Done!"
    echo " "
fi

#--------------------------------------------------------------------#
echo " "
echo "+++++++++++++++++++++++++++++++++++++++++++++"
echo "INFO ($this_script): All Stages Done Successfully!"
date
echo "+++++++++++++++++++++++++++++++++++++++++++++"
echo " "
#--------------------------------------------------------------------#

