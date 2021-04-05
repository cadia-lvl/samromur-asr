#!/usr/bin/env bash

set -e

# This script is called from local/chain/run_tdnn_lstm.sh. It contains the common feature
# preparation and iVector-related parts of the script. See those scripts for examples of usage.

stage=1
generate_alignments=false # Depends on whether we are doing speech perturbations
speed_perturb=false

exp=exp
data=data

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
#train_set=train_okt2017_fourth

gmm_dir=$exp/${gmm}
ali_dir=$exp/${gmm}_ali_${train_set}$suffix

mfccdir=$exp/mfcc

if [[ $inputdata == *"10h"* ]]; then
  subset_size=5000

elif [[ $inputdata == *"20h"* ]]; then
  subset_size=10000

elif [[ $inputdata == *"40h"* ]]; then
  subset_size=20000 

else    
  subset_size=40000
fi 



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
    steps/make_mfcc.sh --nj 80 \
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
    steps/align_fmllr.sh --nj 80 \
                         --cmd "$train_cmd --time 2-00" \
                         $data/${train_set}${suffix} \
                         $langdir \
                         $gmm_dir \
                         $ali_dir || exit 1
  fi
  train_set=${train_set}${suffix}
fi

if [ $stage -le 3 ]; then
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
  
  steps/make_mfcc.sh --nj 80 \
            --mfcc-config conf/mfcc_hires.conf \
            --cmd "$train_cmd --time 2-00" \
            $data/${train_set}_hires \
            $exp/logs/make_mfcc \
            $mfccdir
  
  steps/compute_cmvn_stats.sh $data/${train_set}_hires \
                              $exp/make_hires/${train_set} \
                              $mfccdir;
  
  # Remove the small number of utterances that couldn't be extracted for some
  # reason (e.g. too short; no such file).
  utils/fix_data_dir.sh $data/${train_set}_hires;
  

  # For the libri data. We only run this once
  
  #for data_set in dev_clean test_clean; do
  #  echo "Creating mfcc's for $data_set"
    # Create MFCCs for the dev/eval sets

  #  utils/copy_data_dir.sh $testdatadir/$data_set data_ISP/libri/${data_set}_hires
    
  #  steps/make_mfcc.sh --cmd "$train_cmd" \
  #                     --nj 80 \
  #                     --mfcc-config conf/mfcc_hires.conf \
  #                     data_ISP/libri/${data_set}_hires \
  #                     exp_ISP/libri/log/${data_set}_hires \
  #                     exp_ISP/libri/mfcc/${data_set}_hires;

  #  steps/compute_cmvn_stats.sh data_ISP/libri/${data_set}_hires \
  #                              exp_ISP/libri/log/${data_set}_hires \
  #                              exp_ISP/libri/mfcc/${data_set}_hires;

  #  utils/validate_data_dir.sh data_ISP/libri/${data_set}_hires || utils/fix_data_dir.sh data_ISP/libri/${data_set}_hires 
  #  echo "Done mfcc's for $data_set"
  # done
  
  # For the isl data. We only run this once
  #for data_set in sm_dev sm_test althingi_dev althingi_test; do
  #  echo "Creating mfcc's for $data_set"
    # Create MFCCs for the dev/eval sets

  #  utils/copy_data_dir.sh $testdatadir/$data_set $testdatadir/${data_set}_hires
    
  #  steps/make_mfcc.sh --cmd "$train_cmd" \
  #                     --nj 80 \
  #                     --mfcc-config conf/mfcc_hires.conf \
  #                     data_ISP/sm/${data_set}_hires \
  #                     exp_ISP/sm/log/${data_set}_hires \
  #                     exp_ISP/sm/mfcc/${data_set}_hires;

  # steps/compute_cmvn_stats.sh data_ISP/sm/${data_set}_hires \
  #                              exp_ISP/sm/log/${data_set}_hires \
  #                              exp_ISP/sm/mfcc/${data_set}_hires;

  #  utils/validate_data_dir.sh data_ISP/sm/${data_set}_hires || utils/fix_data_dir.sh data_ISP/sm/${data_set}_hires 
  #  echo "Done mfcc's for $data_set"
  #done

  # We need to make diffrent sized subset for the diffrent datasets
  utils/subset_data_dir.sh $data/${train_set}_hires \
                           $subset_size \
                           $data/${train_set}_${subset_size}k_hires

fi




if [ $stage -le 5 ]; then
  echo ===========================================================================
  echo "               Computing a PCA transform			                "
  echo ============================================================================

  echo "$0: computing a PCA transform from the hires data."

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
                                        --nj 80 --num-frames 200000 \
                                        $data/${train_set}_${subset_size}k_hires \
                                        512 \
                                        $exp/nnet3/pca \
                                        $exp/nnet3/diag_ubm
fi

if [ $stage -le 7 ]; then
  echo ===========================================================================
  echo "               Extracting iVecotrs			                "
  echo ============================================================================

  # iVector extractors can be sensitive to the amount of data, but this one has a
  # fairly small dim (defaults to 100) so we don't use all of it, we use just the
  # 100k subset (~15% of the data).
  # NOTE! I'm doing this for a small set. Use all
  echo "$0: training the iVector extractor"
  steps/online/nnet2/train_ivector_extractor.sh --cmd "$train_cmd --time 1-12" \
                                                --nj 80 \
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
                                                --nj 80 \
                                                ${temp_data_root}/${train_set}_hires_max2 \
                                                $exp/nnet3/extractor \
                                                $ivectordir
  
  # Also extract iVectors for the test/dev data
  if [[ $inputdata == *"isl"* ]]; then
    for data_set in sm_dev sm_test althingi_dev althingi_test; do
      echo "Extracting Ivectors from $data_set"

      steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" \
                                                  --nj 50 \
                                                  data_ISP/sm/${data_set}_hires \
                                                  $exp/nnet3/extractor \
                                                  $exp/nnet3/ivectors_${data_set} \
                                                  || exit 1;
    done
  elif [[ $inputdata == *"libri"* ]]; then
      for data_set in dev_clean test_clean; do
        echo "Extracting Ivectors from $data_set"
        steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" \
                                                      --nj 50 \
                                                      data_ISP/libri/${data_set}_hires \
                                                      $exp/nnet3/extractor \
                                                      $exp/nnet3/ivectors_${data_set} \
                                                      || exit 1;
    done
  else
    echo "Somethings wrong check path $inputdata"
    exit 1

  fi 
fi

exit 0;
