#-*- coding: utf-8 -*- 
########################################################################
#nemo_training.py

#Author   : Carlos Daniel Hernández Mena
#Date     : December 05th, 2021
#Location : Reykjavík University

#Usage:

#	$ python3 nemo_training.py <num_gpus> <num_jobs> <num_epochs> <experiment_path> <config_file> <training_manifest> <dev_manifest>

#Example:

#    #Start the training process.
#    python3 $exp_dir/nemo_training.py $num_gpus $nj_train $num_epochs $exp_dir \
#                                      conf/Config_QuartzNet15x5_Icelandic.yaml \
#                                      data/train/train_manifest.json \
#                                      data/dev/dev_manifest.json

#Description:

#This script performs a training process in NeMo.

#Notice: This program is intended for Python 3
########################################################################
#Imports

import sys
import re
import os

#Importing NeMo Modules
import nemo
import nemo.collections.asr as nemo_asr

########################################################################
#Input Parameters

NUM_GPUS=int(sys.argv[1])

NUM_JOBS=int(sys.argv[2])

NUM_EPOCHS=int(sys.argv[3])

EXPERIMENT_PATH=sys.argv[4]

#Model Architecture
config_path = sys.argv[5]

#Path to our training manifest
train_manifest = sys.argv[6]

#Path to our validation manifest.
#The development portion in this case.
dev_manifest = sys.argv[7]

########################################################################
# Reading Model definition
from ruamel.yaml import YAML

yaml = YAML(typ='safe')
with open(config_path) as f:
    model_definition = yaml.load(f)
#ENDWITH

########################################################################
# Creating the trainer

import pytorch_lightning as pl
from pytorch_lightning import loggers as pl_loggers
from pytorch_lightning.plugins import DDPPlugin

#Create a lightning log object
tb_logger = pl_loggers.TensorBoardLogger(save_dir=EXPERIMENT_PATH,name="lightning_logs")

#Create the trainer object
#trainer = pl.Trainer(gpus=NUM_GPUS, max_epochs=NUM_EPOCHS,logger=tb_logger,strategy="ddp")
trainer = pl.Trainer(gpus=NUM_GPUS, max_epochs=NUM_EPOCHS,logger=tb_logger,strategy=DDPPlugin(find_unused_parameters=False))

########################################################################
#Adjusting model parameters
from omegaconf import DictConfig

#Passing the path of the train manifest to the model
model_definition['model']['train_ds']['manifest_filepath'] = train_manifest
#Specifying the number of jobs of the training process
model_definition['model']['train_ds']['num_workers'] = NUM_JOBS

#Passing the path of the test manifest to the model
model_definition['model']['validation_ds']['manifest_filepath'] = dev_manifest
#Specifying the number of jobs of the test process
model_definition['model']['validation_ds']['num_workers'] = NUM_JOBS

#Specifying the Learning Rate
model_definition['model']['optim']['lr'] = 0.05

#Specifying the Weight Decay
model_definition['model']['optim']['weight_decay'] = 0.0001

#Specifying the Dropout
model_definition['dropout']=0.2

#Specifying number of repetitions
model_definition['repeat']=1

########################################################################
#Adjusting parameters for the SpecAugment

#Rectangles placed ramdomly
model_definition['model']['spec_augment']['rect_masks'] = 5
#Vertical Stripes (Time)
model_definition['model']['spec_augment']['rect_time'] = 120
#Horintal Stripes (Frequency)
model_definition['model']['spec_augment']['rect_freq'] = 50

########################################################################
#Creating the ASR system which is a NeMo object
nemo_asr_model = nemo_asr.models.EncDecCTCModel(cfg=DictConfig(model_definition['model']), trainer=trainer)

########################################################################
#START TRAINING!
trainer.fit(nemo_asr_model)

########################################################################
#Saving the Model

#Calculating the current date and time to label the checkpoint
from datetime import datetime
time_now=str(datetime.now())
time_now=time_now.replace(" ","_")

#Creating the Checkpoint directory
dir_checkpoints=os.path.join(EXPERIMENT_PATH,"CHECKPOINTS")
name_checkpoints= "model_weights_"+time_now+".ckpt"
if not os.path.exists(dir_checkpoints):
	os.mkdir(dir_checkpoints)
#ENDIF

#Save the checkpoint
path_checkpoint=os.path.join(dir_checkpoints, name_checkpoints)
nemo_asr_model.save_to(path_checkpoint)

########################################################################
#Write the path to the last checkpoint in an output file
file_path=os.path.join(EXPERIMENT_PATH,"final_model.path")
file_checkpoint=open(file_path,'w')
file_checkpoint.write(path_checkpoint)
file_checkpoint.close()

print("\nINFO: Final Checkpoint in "+path_checkpoint)

########################################################################

print("\nINFO: MODEL SUCCESFULLY TRAINED!")

########################################################################

