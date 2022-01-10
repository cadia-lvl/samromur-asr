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
# To be run from the SAMROMUR_DEEPSPEECH directory

echo "-----------------------------------"
echo "Initialization ..."
echo "-----------------------------------"

#--------------------------------------------------------------------#
#Setting up important paths and variables
#--------------------------------------------------------------------#
# NOTE! In the future the ASR data, LM training text and pronunciation 
#dictionary will be downloaded from online first, e.g. Clarin

corpus_root=/home/carlosm/CORPUS/samromur_21.05
deepspeech_scorer=/home/carlosm/CORPUS/DeepSpeech_Scorers/10_trials_optim_kenlm.scorer

#Destination of the corpus in wav version
corpus_wav_path=/home/carlosm/CORPUS
corpus_wav_name=samromur_21.05_wav

#--------------------------------------------------------------------#
#CONTROL PANEL
#--------------------------------------------------------------------#

#__________________________________________________#
#If you are not in TERRA, choose the GPUs with this:
#CUDA_DEVICE_ORDER="PCI_BUS_ID"
#CUDA_VISIBLE_DEVICES="0,1,2,3,4,5"
#__________________________________________________#
#If you are in TERRA, select an specific GPU
#in the script: steps/evaluate_tflite.py
#See the comments there.
#__________________________________________________#

nj_decode=30
nj_train=30

#Note: In TERRA, I recommend the use of only 1 GPU.
num_gpus=1
    
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

[ ! -f "$deepspeech_scorer" ] && echo "$0: expected $deepspeech_scorer to exist" && exit 1;

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
    
    python3 local/create_csvs.py $corpus_wav_path/$corpus_wav_name
    
    mkdir -p data/
    
    mkdir -p data/train
    mkdir -p data/test
    mkdir -p data/dev
    
    mv train.csv data/train
    mv test.csv data/test
    mv dev.csv data/dev
        
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
    num_epochs=10
    learning_rate=0.0001

    train_batch_size=$nj_train
    dev_batch_size=$nj_decode
    test_batch_size=$nj_decode
    
    exp_name=model_training
    exp_dir=exp/$exp_name
    mkdir -p exp
    mkdir -p exp/$exp_name
    
    checkpoints_dir=exp/$exp_name/CHECKPOINTS
    model_dir=exp/$exp_name/MODEL
    mkdir -p $checkpoints_dir
    mkdir -p $model_dir
    
    cp steps/DeepSpeech.py $exp_dir
    cp local/Prefabricated_Files/alphabet.txt $exp_dir

    #Start the training process.
    python3 -u $exp_dir/DeepSpeech.py \
        --train_files data/train/train.csv \
        --dev_files data/dev/dev.csv \
        --test_files data/test/test.csv \
        --alphabet_config_path $exp_dir/alphabet.txt \
        --train_batch_size $train_batch_size \
        --dev_batch_size $dev_batch_size \
        --test_batch_size $test_batch_size \
        --epochs $num_epochs \
        --learning_rate $learning_rate \
        --max_to_keep 1 \
        --export_dir $model_dir \
        --checkpoint_dir $checkpoints_dir\
        "$@"
    
    echo " "
    echo "INFO ($this_script): Stage $current_stage Done!"
    echo " "
fi

#--------------------------------------------------------------------#
#Evaluation of the Development Set
#--------------------------------------------------------------------#
current_stage=3
if  [ $current_stage -ge $from_stage ] && [ $current_stage -le $to_stage ]; then
    echo "-----------------------------------"
    echo "Stage $current_stage: Evaluation of the Development Set"
    echo "-----------------------------------"
    
    #Prepare the experiment for dev
    exp_name=dev_evaluation
    exp_dir=exp/$exp_name
    mkdir -p exp
    mkdir -p exp/$exp_name
    
    wer_results="$exp_dir/wer_report"
        
    cp steps/evaluate_tflite.py $exp_dir
    cp local/Prefabricated_Files/alphabet.txt $exp_dir

    #Start the evaluation process
    python3 $exp_dir/evaluate_tflite.py \
        --model exp/model_training/MODEL/output_graph.pb \
        --alphabet_config_path $exp_dir/alphabet.txt \
        --scorer $deepspeech_scorer \
        --csv data/dev/dev.csv \
        --proc $num_gpus \
        --dump $exp_dir > $wer_results

    #Copy the resulting files to the experiment directory.
    [ -f "exp/dev_evaluation.txt" ] && mv -f exp/dev_evaluation.txt $exp_dir/dev_evaluation.ref;
    [ -f "exp/dev_evaluation.out" ] && mv -f exp/dev_evaluation.out $exp_dir/dev_evaluation.hyp;
    
    echo " "
    echo "INFO ($this_script): Stage $current_stage Done!"
    echo " "
fi

#--------------------------------------------------------------------#
#Evaluation of the Test Set
#--------------------------------------------------------------------#
current_stage=4
if  [ $current_stage -ge $from_stage ] && [ $current_stage -le $to_stage ]; then
    echo "-----------------------------------"
    echo "Stage $current_stage: Evaluation of the Test Set"
    echo "-----------------------------------"
    
    #Prepare the experiment for test
    exp_name=test_evaluation
    exp_dir=exp/$exp_name
    mkdir -p exp
    mkdir -p exp/$exp_name
    
    wer_results="$exp_dir/wer_report"
        
    cp steps/evaluate_tflite.py $exp_dir
    cp local/Prefabricated_Files/alphabet.txt $exp_dir
    
    #Start the evaluation process
    python3 $exp_dir/evaluate_tflite.py \
        --model exp/model_training/MODEL/output_graph.pb \
        --alphabet_config_path $exp_dir/alphabet.txt \
        --scorer $deepspeech_scorer \
        --csv data/test/test.csv \
        --proc $num_gpus \
        --dump $exp_dir > $wer_results

    #Copy the resulting files to the experiment directory.
    [ -f "exp/test_evaluation.txt" ] && mv -f exp/test_evaluation.txt $exp_dir/test_evaluation.ref;
    [ -f "exp/test_evaluation.out" ] && mv -f exp/test_evaluation.out $exp_dir/test_evaluation.hyp;
    
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
    deepspeech_model=utils/example_model.pb
    audio_in=utils/example_audio.wav
    
    deepspeech --model $deepspeech_model \
               --audio $audio_in
    
    echo " "
    echo "INFO ($this_script): Stage $current_stage Done!"
    echo " "
fi

#--------------------------------------------------------------------#
#Example: Transcribe 1 audio with a DeepSpeech Scorer
#--------------------------------------------------------------------#
current_stage=7
if  [ $current_stage -ge $from_stage ] && [ $current_stage -le $to_stage ]; then
    echo "-----------------------------"
    echo "Stage $current_stage: Example: Transcribe 1 audio with a DeepSpeech Scorer"
    echo "-----------------------------"

    #Prepare the experiment
    deepspeech_model=utils/example_model.pb
    scorer=utils/example.scorer
    audio_in=utils/example_audio.wav
    
    deepspeech --model $deepspeech_model \
               --scorer $scorer \
               --audio $audio_in

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

