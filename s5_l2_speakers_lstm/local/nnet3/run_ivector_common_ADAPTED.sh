#!/usr/bin/env bash
#--------------------------------------------------------------------#
# This script is called from local/nnet3/run_tdnn.sh and local/chain/run_tdnn.sh (and may eventually
# be called by more scripts).  It contains the common feature preparation and iVector-related parts
# of the script.  See those scripts for examples of usage.
#--------------------------------------------------------------------#
#Exit immediately in case of error.
set -e -o pipefail
#--------------------------------------------------------------------#
stage=0
nj=30
min_seg_len=1.55  # min length in seconds... we do this because chain training
                  # will discard segments shorter than 1.5 seconds.   Must remain in sync
                  # with the same option given to prepare_lores_feats_and_alignments.sh
train_set=train_cleaned   # you might set this to e.g. train.
gmm=tri3_cleaned          # This specifies a GMM-dir from the features of the type you're training the system on;
                         # it should contain alignments for 'train_set'.

num_threads_ubm=8
nnet3_affix=_cleaned     # affix for exp/nnet3 directory to put iVector stuff in, so it
                         # becomes exp/nnet3_cleaned or whatever.
#--------------------------------------------------------------------#
#Setting up Kaldi paths and commands
. ./cmd.sh
. ./path.sh
. utils/parse_options.sh

#--------------------------------------------------------------------#
gmm_dir=exp/${gmm}
ali_dir=exp/${gmm}_ali_${train_set}_sp_comb

#Check the existance of important files.
for f in data/${train_set}/feats.scp ${gmm_dir}/final.mdl; do
  if [ ! -f $f ]; then
    echo "=========="
    echo "$0: expected file $f to exist"
    echo "=========="
    exit 1
  fi
done

#--------------------------------------------------------------------#
#Check the existance of High Resolution files.
#--------------------------------------------------------------------#
if [ $stage -le 2 ] && [ -f data/${train_set}_sp_hires/feats.scp ]; then
  echo "=========="
  echo "$0: data/${train_set}_sp_hires/feats.scp already exists."
  echo "=========="
  echo " ... Please either remove it, or rerun this script with stage > 2."
  exit 1
fi

#--------------------------------------------------------------------#
#Preparing directory for speed-perturbed data
#--------------------------------------------------------------------#
if [ $stage -le 1 ]; then
  echo "=========="
  echo "$0: preparing directory for speed-perturbed data"
  echo "=========="
  utils/data/perturb_data_dir_speed_3way.sh data/${train_set} data/${train_set}_sp
fi

#--------------------------------------------------------------------#
#Creating high-resolution MFCC features
#--------------------------------------------------------------------#
if [ $stage -le 2 ]; then
  echo "=========="
  echo "$0: creating high-resolution MFCC features"
  echo "=========="

  # this shows how you can split across multiple file-systems.  we'll split the
  # MFCC dir across multiple locations.  You might want to be careful here, if you
  # have multiple copies of Kaldi checked out and run the same recipe, not to let
  # them overwrite each other.
  mfccdir=data/${train_set}_sp_hires/data
  if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $mfccdir/storage ]; then
    utils/create_split_dir.pl /export/b0{5,6,7,8}/$USER/kaldi-data/mfcc/tedlium-$(date +'%m_%d_%H_%M')/s5/$mfccdir/storage $mfccdir/storage
  fi

  for datadir in ${train_set}_sp dev test; do
    utils/copy_data_dir.sh data/$datadir data/${datadir}_hires
  done

  # do volume-perturbation on the training data prior to extracting hires
  # features; this helps make trained nnets more invariant to test data volume.
  utils/data/perturb_data_dir_volume.sh data/${train_set}_sp_hires

  for datadir in ${train_set}_sp dev test; do
    steps/make_mfcc.sh --nj $nj --mfcc-config conf/mfcc_hires.conf \
      --cmd "$train_cmd" data/${datadir}_hires
    steps/compute_cmvn_stats.sh data/${datadir}_hires
    utils/fix_data_dir.sh data/${datadir}_hires
  done
fi

#--------------------------------------------------------------------#
#Combining short segments of speed-perturbed high-resolution MFCC training data
#--------------------------------------------------------------------#
if [ $stage -le 3 ]; then
  echo "=========="
  echo "$0: combining short segments of speed-perturbed high-resolution MFCC training data"
  echo "=========="
  # we have to combine short segments or we won't be able to train chain models
  # on those segments.
  utils/data/combine_short_segments.sh \
     data/${train_set}_sp_hires $min_seg_len data/${train_set}_sp_hires_comb

  # just copy over the CMVN to avoid having to recompute it.
  cp data/${train_set}_sp_hires/cmvn.scp data/${train_set}_sp_hires_comb/
  utils/fix_data_dir.sh data/${train_set}_sp_hires_comb/
fi

#--------------------------------------------------------------------#
#Selecting segments of hires training data that were also present in the original training data.
#--------------------------------------------------------------------#
if [ $stage -le 4 ]; then
  echo "=========="
  echo "$0: selecting segments of hires training data that were also present in the"
  echo " ... original training data."
  echo "=========="

  # note, these data-dirs are temporary; we put them in a sub-directory
  # of the place where we'll make the alignments.
  temp_data_root=exp/nnet3${nnet3_affix}/tri5
  mkdir -p $temp_data_root

  utils/data/subset_data_dir.sh --utt-list data/${train_set}/feats.scp \
          data/${train_set}_sp_hires $temp_data_root/${train_set}_hires

  # note: essentially all the original segments should be in the hires data.
  n1=$(wc -l <data/${train_set}/feats.scp)
  n2=$(wc -l <$temp_data_root/${train_set}_hires/feats.scp)
  if [ $n1 != $n1 ]; then
    echo "=========="
    echo "$0: warning: number of feats $n1 != $n2, if these are very different it could be bad."
    echo "=========="
  fi

  echo "=========="
  echo "$0: training a system on the hires data for its LDA+MLLT transform, in order to produce the diagonal GMM."
  echo "=========="
  if [ -e exp/nnet3${nnet3_affix}/tri5/final.mdl ]; then
    # we don't want to overwrite old stuff, ask the user to delete it.
  echo "=========="
    echo "$0: exp/nnet3${nnet3_affix}/tri5/final.mdl already exists: "
    echo " ... please delete and then rerun, or use a later --stage option."
  echo "=========="
    exit 1;
  fi
  steps/train_lda_mllt.sh --cmd "$train_cmd" --num-iters 7 --mllt-iters "2 4 6" \
     --splice-opts "--left-context=3 --right-context=3" \
     3000 10000 $temp_data_root/${train_set}_hires data/lang \
      $gmm_dir exp/nnet3${nnet3_affix}/tri5
fi

#--------------------------------------------------------------------#
#Computing a subset of data to train the diagonal UBM.
#--------------------------------------------------------------------#
if [ $stage -le 5 ]; then
  echo "=========="
  echo "$0: computing a subset of data to train the diagonal UBM."
  echo "=========="

  mkdir -p exp/nnet3${nnet3_affix}/diag_ubm
  temp_data_root=exp/nnet3${nnet3_affix}/diag_ubm

  # train a diagonal UBM using a subset of about a quarter of the data
  # we don't use the _comb data for this as there is no need for compatibility with
  # the alignments, and using the non-combined data is more efficient for I/O
  # (no messing about with piped commands).
  num_utts_total=$(wc -l <data/${train_set}_sp_hires/utt2spk)
  num_utts=$[$num_utts_total/4]
  utils/data/subset_data_dir.sh data/${train_set}_sp_hires \
      $num_utts ${temp_data_root}/${train_set}_sp_hires_subset

  echo "=========="
  echo "$0: training the diagonal UBM."
  echo "=========="
  # Use 512 Gaussians in the UBM.
  steps/online/nnet2/train_diag_ubm.sh --nj 10 --cmd "utils/run.pl" \
    --num-frames 700000 \
    --num-threads $num_threads_ubm \
    ${temp_data_root}/${train_set}_sp_hires_subset 512 \
    exp/nnet3${nnet3_affix}/tri5 exp/nnet3${nnet3_affix}/diag_ubm
fi

#--------------------------------------------------------------------#
#Training the iVector extractor
#--------------------------------------------------------------------#
if [ $stage -le 6 ]; then
  # Train the iVector extractor.  Use all of the speed-perturbed data since iVector extractors
  # can be sensitive to the amount of data.  The script defaults to an iVector dimension of
  # 100.
  echo "=========="
  echo "$0: training the iVector extractor"
  echo "=========="
  steps/online/nnet2/train_ivector_extractor.sh --cmd "$train_cmd" --nj 10 \
    data/${train_set}_sp_hires exp/nnet3${nnet3_affix}/diag_ubm exp/nnet3${nnet3_affix}/extractor || exit 1;
fi

#--------------------------------------------------------------------#
#Extract iVectors on the speed-perturbed training data after combining short segments
#--------------------------------------------------------------------#
if [ $stage -le 7 ]; then
  # note, we don't encode the 'max2' in the name of the ivectordir even though
  # that's the data we extract the ivectors from, as it's still going to be
  # valid for the non-'max2' data, the utterance list is the same.
  echo "=========="
  echo "Extract iVectors on the speed-perturbed training data after combining short segments"
  echo "=========="
  ivectordir=exp/nnet3${nnet3_affix}/ivectors_${train_set}_sp_hires_comb
  if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $ivectordir/storage ]; then
    utils/create_split_dir.pl /export/b0{5,6,7,8}/$USER/kaldi-data/ivectors/tedlium-$(date +'%m_%d_%H_%M')/s5/$ivectordir/storage $ivectordir/storage
  fi
  # We extract iVectors on the speed-perturbed training data after combining
  # short segments, which will be what we train the system on.  With
  # --utts-per-spk-max 2, the script pairs the utterances into twos, and treats
  # each of these pairs as one speaker; this gives more diversity in iVectors..
  # Note that these are extracted 'online'.

  # having a larger number of speakers is helpful for generalization, and to
  # handle per-utterance decoding well (iVector starts at zero).
  temp_data_root=${ivectordir}
  utils/data/modify_speaker_info.sh --utts-per-spk-max 2 \
    data/${train_set}_sp_hires_comb ${temp_data_root}/${train_set}_sp_hires_comb_max2

  steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj $nj \
    ${temp_data_root}/${train_set}_sp_hires_comb_max2 \
    exp/nnet3${nnet3_affix}/extractor $ivectordir

  # Also extract iVectors for the test data, but in this case we don't need the speed
  # perturbation (sp) or small-segment concatenation (comb).
  echo "=========="
  echo "Also extract iVectors for the test data, but in this case we don't need the speed"
  echo "=========="
  for data in dev test; do
    steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj "$nj" \
      data/${data}_hires exp/nnet3${nnet3_affix}/extractor \
      exp/nnet3${nnet3_affix}/ivectors_${data}_hires
  done
fi

#--------------------------------------------------------------------#
#Checking the existance of some files
#--------------------------------------------------------------------#
if [ -f data/${train_set}_sp/feats.scp ] && [ $stage -le 9 ]; then
  echo "=========="
  echo "$0: $feats already exists.  Refusing to overwrite the features "
  echo " to avoid wasting time.  Please remove the file and continue if you really mean this."
  echo "=========="
  exit 1;
fi

#--------------------------------------------------------------------#
#Preparing directory for low-resolution speed-perturbed data (for alignment)
#--------------------------------------------------------------------#
if [ $stage -le 8 ]; then
  echo "=========="
  echo "$0: preparing directory for low-resolution speed-perturbed data (for alignment)"
  echo "=========="
  utils/data/perturb_data_dir_speed_3way.sh \
    data/${train_set} data/${train_set}_sp
fi

#--------------------------------------------------------------------#
#Making MFCC features for low-resolution speed-perturbed data
#--------------------------------------------------------------------#
if [ $stage -le 9 ]; then
  echo "=========="
  echo "$0: making MFCC features for low-resolution speed-perturbed data"
  echo "=========="
  steps/make_mfcc.sh --nj $nj \
    --cmd "$train_cmd" data/${train_set}_sp
  steps/compute_cmvn_stats.sh data/${train_set}_sp
  echo " "
  echo "$0: fixing input data-dir to remove nonexistent features, in case some "
  echo ".. speed-perturbed segments were too short."
  echo " "
  utils/fix_data_dir.sh data/${train_set}_sp
fi

#--------------------------------------------------------------------#
#Combining short segments of low-resolution speed-perturbed  MFCC data
#--------------------------------------------------------------------#
if [ $stage -le 10 ]; then
  echo "=========="
  echo "$0: combining short segments of low-resolution speed-perturbed  MFCC data"
  echo "=========="
  src=data/${train_set}_sp
  dest=data/${train_set}_sp_comb
  utils/data/combine_short_segments.sh $src $min_seg_len $dest
  # re-use the CMVN stats from the source directory, since it seems to be slow to
  # re-compute them after concatenating short segments.
  cp $src/cmvn.scp $dest/
  utils/fix_data_dir.sh $dest
fi

#--------------------------------------------------------------------#
#Aligning with the perturbed, short-segment-combined low-resolution data
#--------------------------------------------------------------------#
if [ $stage -le 11 ]; then
  if [ -f $ali_dir/ali.1.gz ]; then
  echo "=========="
    echo "$0: alignments in $ali_dir appear to already exist.  Please either remove them "
    echo " ... or use a later --stage option."
  echo "=========="
    exit 1
  fi
  
  echo "=========="
  echo "$0: aligning with the perturbed, short-segment-combined low-resolution data"
  echo "=========="
  steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" \
         data/${train_set}_sp_comb data/lang $gmm_dir $ali_dir
fi

#--------------------------------------------------------------------#
exit 0;
#--------------------------------------------------------------------#

