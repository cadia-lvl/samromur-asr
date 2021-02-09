#!/bin/bash

set -e

# This script is called from local/chain/run_tdnn_lstm.sh. It contains the common feature
# preparation and iVector-related parts of the script. See those scripts for examples of usage.

stage=1
generate_alignments=false # Depends on whether we are doing speech perturbations
speed_perturb=false

# Defined in conf/path.conf, default to /mnt/scratch/inga/{exp,data,mfcc}
exp=
data=
mfcc=

. ./cmd.sh
. ./path.sh # runs conf/path.conf
. ./utils/parse_options.sh

if [ ! $# = 4 ]; then
  echo "This script creates high-resolution MFCC features for the training data,"
  echo "which is either speed perturbed or not. If we speed perturb, then new alignments"
  echo "are also obtained. An ivector extractor is also trained and ivectors extracted"
  echo "for both training and test sets."
  echo ""
  echo "Usage: $0 [options] <input-training-data-dir> <dir-with-test-sets> <lang-dir> <gmm-name>"
  echo " e.g.: $0 data/train data data/lang tri5"
  echo ""
  echo "Options:"
  echo "    --speed-perturb         # apply speed perturbations, default: true"
  echo "    --generate-alignments   # obtain the alignments of the perturbed data"
  exit 1;
fi

inputdata=$1
testdatadir=$2
langdir=$3
gmm=$4

suffix=
$speed_perturb && suffix=_sp

# perturbed data preparation
train_set=$(basename $inputdata)
#train_set=train_okt2017_fourth

gmm_dir=$exp/${gmm}
ali_dir=$exp/${gmm}_ali_${train_set}$suffix


if [ "$speed_perturb" == "true" ]; then
  if [ $stage -le 1 ]; then
    #Although the nnet will be trained by high resolution data, we still have to perturbe the normal data to get the alignment
    # _sp stands for speed-perturbed
    echo "$0: preparing directory for low-resolution speed-perturbed data (for alignment)"
    utils/data/perturb_data_dir_speed_3way.sh $inputdata $data/${train_set}${suffix}
    echo "$0: making MFCC features for low-resolution speed-perturbed data" 
    steps/make_mfcc.sh --nj 100 --cmd "$train_cmd --time 2-00" \
      $data/${train_set}${suffix} || exit 1
    steps/compute_cmvn_stats.sh $data/${train_set}${suffix} || exit 1
    utils/fix_data_dir.sh $data/${train_set}${suffix} || exit 1
  fi

  if [ $stage -le 2 ] && [ "$generate_alignments" == "true" ]; then
    #obtain the alignment of the perturbed data
    steps/align_fmllr.sh --nj 100 --cmd "$decode_cmd --time 3-00" \
      $data/${train_set}${suffix} $langdir $gmm_dir $ali_dir || exit 1
  fi
  train_set=${train_set}${suffix}
fi

if [ $stage -le 3 ]; then
  # Create high-resolution MFCC features (with 40 cepstra instead of 13).
  # this shows how you can split across multiple file-systems. we'll split the
  # MFCC dir across multiple locations.  You might want to be careful here, if you
  # have multiple copies of Kaldi checked out and run the same recipe, not to let
  # them overwrite each other.
  echo "$0: creating high-resolution MFCC features"
  
  # the 100k_nodup directory is copied seperately, as
  # we want to use exp/tri1b_ali_100k_nodup for ivector extractor training
  # the main train directory might be speed_perturbed
  if [ "$speed_perturb" == "true" ]; then
    utils/copy_data_dir.sh $data/$train_set $data/${train_set}_hires
  else
    utils/copy_data_dir.sh $inputdata $data/${train_set}_hires
  fi
  
  # do volume-perturbation on the training data prior to extracting hires
  # features; this helps make trained nnets more invariant to test data volume.
  utils/data/perturb_data_dir_volume.sh $data/${train_set}_hires

  steps/make_mfcc.sh \
    --nj 100 --mfcc-config conf/mfcc_hires.conf \
    --cmd "$decode_cmd --time 3-00" \
    $data/${train_set}_hires \
    $exp/make_hires/$train_set $mfcc;
  
  steps/compute_cmvn_stats.sh $data/${train_set}_hires $exp/make_hires/${train_set} $mfcc;

  # Remove the small number of utterances that couldn't be extracted for some
  # reason (e.g. too short; no such file).
  utils/fix_data_dir.sh $data/${train_set}_hires;

  for dataset in dev eval; do
    # Create MFCCs for the dev/eval sets
    utils/copy_data_dir.sh $testdatadir/$dataset $data/${dataset}_hires
    steps/make_mfcc.sh --cmd "$train_cmd" --nj 30 --mfcc-config conf/mfcc_hires.conf \
      $data/${dataset}_hires $exp/make_hires/$dataset $mfcc;
    steps/compute_cmvn_stats.sh $data/${dataset}_hires $exp/make_hires/$dataset $mfcc;
    utils/fix_data_dir.sh $data/${dataset}_hires  # remove segments with problems
  done

  # Take 35k utterances (about 1/20th of the data (if using train_okt_fourth)) this will be used
  # for the diagubm training
  # The 100k subset will be used for ivector extractor training
  utils/subset_data_dir.sh $data/${train_set}_hires 35000 $data/${train_set}_35k_hires
  utils/subset_data_dir.sh $data/${train_set}_hires 100000 $data/${train_set}_100k_hires
fi

if [ $stage -le 5 ]; then
  echo "$0: computing a PCA transform from the hires data."
  steps/online/nnet2/get_pca_transform.sh --cmd "$train_cmd --time 2-00" \
    --splice-opts "--left-context=3 --right-context=3" \
    --max-utts 10000 --subsample 2 \
    $data/${train_set}_35k_hires $exp/nnet3/pca
fi

if [ $stage -le 6 ]; then
  # To train a diagonal UBM we don't need very much data, so use the smallest subset.
  echo "$0: training the diagonal UBM."
  steps/online/nnet2/train_diag_ubm.sh  --cmd "$train_cmd" --nj 30 --num-frames 200000 \
    $data/${train_set}_35k_hires 512 $exp/nnet3/pca $exp/nnet3/diag_ubm
fi

if [ $stage -le 7 ]; then
  # iVector extractors can be sensitive to the amount of data, but this one has a
  # fairly small dim (defaults to 100) so we don't use all of it, we use just the
  # 100k subset (~15% of the data).
  echo "$0: training the iVector extractor"
  steps/online/nnet2/train_ivector_extractor.sh --cmd "$train_cmd --time 1-12" --nj 10 \
    $data/${train_set}_100k_hires $exp/nnet3/diag_ubm $exp/nnet3/extractor || exit 1;
fi

if [ $stage -le 8 ]; then
  # We extract iVectors on the speed-perturbed training data after combining
  # short segments, which will be what we train the system on.  With
  # --utts-per-spk-max 2, the script pairs the utterances into twos, and treats
  # each of these pairs as one speaker; this gives more diversity in iVectors..
  # Note that these are extracted 'online'.

  # note, we don't encode the 'max2' in the name of the ivectordir even though
  # that's the data we extract the ivectors from, as it's still going to be
  # valid for the non-'max2' data, the utterance list is the same.

  ivectordir=$exp/nnet3/ivectors_${train_set}
  
  # having a larger number of speakers is helpful for generalization, and to
  # handle per-utterance decoding well (iVector starts at zero).
  temp_data_root=${ivectordir}
  utils/data/modify_speaker_info.sh --utts-per-spk-max 2 \
    $data/${train_set}_hires ${temp_data_root}/${train_set}_hires_max2

  steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd --time 2-12" --nj 100 \
    ${temp_data_root}/${train_set}_hires_max2 \
    $exp/nnet3/extractor $ivectordir

  # Also extract iVectors for the test data
  for data_set in dev eval; do
    steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj 30 \
      $data/${data_set}_hires $exp/nnet3/extractor $exp/nnet3/ivectors_${data_set} || exit 1;
  done
fi

exit 0;
