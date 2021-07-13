#!/usr/bin/env bash

set -e

# This script is called from local/chain/run_tdnn_lstm.sh. It contains the common feature
# preparation and iVector-related parts of the script. See those scripts for examples of usage.

stage=1
generate_alignments=false # Depends on whether we are doing speech perturbations
speed_perturb=false
create_high_mfcc=true
exp=exp
data=data
nj=30
log=logs
. ./cmd.sh
. ./path.sh
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

gmm_dir=$exp/${gmm}
ali_dir=$exp/${gmm}_ali_${train_set}$suffix

mfccdir=$exp/mfcc
   


if [ "$speed_perturb" == "true" ]; then
  if [ $stage -le 1 ]; then
  echo ===========================================================================
  echo "                		Speed pertrubing data			                "
  echo ============================================================================

    #Although the nnet will be trained by high resolution data, we still have to perturbe the normal data to get the alignment
    # _sp stands for speed-perturbed
    echo "$0: preparing directory for low-resolution speed-perturbed data (for alignment)"
    utils/data/perturb_data_dir_speed_3way.sh $inputdata \
      $data/${train_set}${suffix}

    echo "$0: making MFCC features for low-resolution speed-perturbed data"
    steps/make_mfcc.sh --nj $nj \
      --cmd "$train_cmd --time 2-00" \
      $data/${train_set}${suffix} || exit 1
                        
    steps/compute_cmvn_stats.sh $data/${train_set}${suffix} || exit 1
    
    utils/fix_data_dir.sh $data/${train_set}${suffix} || exit 1
  fi
  
  if [ $stage -le 2 ] && [ "$generate_alignments" == "true" ]; then
    echo ===========================================================================
    echo "                		Generating alignments			                "
    echo ============================================================================

    #obtain the alignment of the perturbed data
    steps/align_fmllr.sh --nj $nj \
      --cmd "$train_cmd --time 2-00" \
      $data/${train_set}${suffix} \
      $langdir \
      $gmm_dir \
      $ali_dir || exit 1
  fi
  train_set=${train_set}${suffix}
fi

if [ $stage -le 3 ] && $create_high_mfcc; then
  echo ===========================================================================
  echo "               Creating high-resolution MFCC features			                "
  echo ============================================================================

  # Create high-resolution MFCC features (with 40 cepstra instead of 13).
  # this shows how you can split across multiple file-systems. we'll split the
  # MFCC dir across multiple locations.  You might want to be careful here, if you
  # have multiple copies of Kaldi checked out and run the same recipe, not to let
  # them overwrite each other.
  echo "$0: creating high-resolution MFCC features"
  
  if [ "$speed_perturb" == "true" ]; then
    utils/copy_data_dir.sh $data/$train_set $data/${train_set}_hires
  else
    utils/copy_data_dir.sh $inputdata $data/${train_set}_hires
  fi
  
  # do volume-perturbation on the training data prior to extracting hires
  # features; this helps make trained nnets more invariant to test data volume.
  utils/data/perturb_data_dir_volume.sh $data/${train_set}_hires
  
  steps/make_mfcc.sh --nj $nj \
    --mfcc-config conf/mfcc_hires.conf \
    --cmd "$train_cmd --time 2-00" \
    $data/${train_set}_hires \
    $log/mfcc/make_mfcc \
    $mfccdir
  
  steps/compute_cmvn_stats.sh $data/${train_set}_hires \
    $log/make_hires/${train_set} \
    $mfccdir;
  
  # Remove the small number of utterances that couldn't be extracted for some
  # reason (e.g. too short; no such file).
  utils/fix_data_dir.sh $data/${train_set}_hires;
fi

if [ $stage -le 5 ]; then
  echo ===========================================================================
  echo "               Computing a PCA transform			                "
  echo ============================================================================
  echo "$0: computing a PCA transform from the hires data."
  subset_size=40000

  # DemoData: To run this script with the demo data we need to change the subset size
  train_size=$(wc -l $data/${train_set}_hires/text | cut -d" " -f1)
  if [ $train_size -le $subset_size ]; then
    subset_size=$train_size
  fi

  utils/subset_data_dir.sh $data/${train_set}_hires \
    $subset_size \
    $data/${train_set}_${subset_size}k_hires

  steps/online/nnet2/get_pca_transform.sh --cmd "$train_cmd --time 2-00" \
    --splice-opts "--left-context=3 --right-context=3" \
    --max-utts 10000 \
    --subsample 2 \
    $data/${train_set}_${subset_size}k_hires \
    $exp/nnet3/pca
fi

if [ $stage -le 6 ]; then
  echo ===========================================================================
  echo "               Training the diagonal UBM			                "
  echo ============================================================================
  # To train a diagonal UBM we don't need very much data, so use the smallest subset.
  echo "$0: training the diagonal UBM."
  steps/online/nnet2/train_diag_ubm.sh  --cmd "$train_cmd" \
    --nj $nj \
    --num-frames 200000 \
    $data/${train_set}_${subset_size}k_hires \
    512 \
    $exp/nnet3/pca \
    $exp/nnet3/diag_ubm
fi

if [ $stage -le 7 ]; then
  echo ===========================================================================
  echo "               Extracting iVecotrs			                "
  echo ============================================================================
  # DemoData: To run this script with the demo data we need to change the number of jobs parameter
  # The script train_ivector_extractor.sh creates nj*num_threads=F many .scp files. But if
  # num_speakers < F we get an error. Default value for num_threads is 4.  
  tmp_nj=$nj
  train_size=$(wc -l $data/${train_set}_hires/spk2utt | cut -d" " -f1)
  if [ $train_size -le $((4*$nj)) ]; then
    tmp_nj=10
  fi
  echo "$0: training the iVector extractor"
  steps/online/nnet2/train_ivector_extractor.sh --cmd "$train_cmd --time 1-12" \
    --nj $tmp_nj \
    $data/${train_set}_hires \
    $exp/nnet3/diag_ubm \
    $exp/nnet3/extractor || exit 1;
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
    $data/${train_set}_hires \
    ${temp_data_root}/${train_set}_hires_max2
  
  steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd --time 2-00" \
    --nj $nj \
    ${temp_data_root}/${train_set}_hires_max2 \
    $exp/nnet3/extractor \
    $ivectordir
  fi

exit 0;
