#!/usr/bin/env bash
# Copyright   2021 Reykjavik University (Author: David Erik Mollberg - de14@ru.is)

# In this script the user can choose diffrent subword tokenziation methods
# and create a new lang folder with a subword l.fst. This is then used to
# decode with a previousely trained acoustic model

export LC_ALL=C

num_jobs=50
num_decode_jobs=30
stage=0
create_venv=false


# Subword specific parameters. 
# Subword method <"bpe", "sp_bpe", "unigram", "morfessor">.
method='unigram'

# Subword unit count parameter. It's usually in the range of few hundrends to a few thousands. 
sw_count=1000

# The boundary marker style. There are a four possible marker styles. 
    # style: example "word like"
    # r:  wo+ rd li+ ke
    # l:  wo +rd li +ke
    # lr: wo+ +rd li+ +ke
    # wb: wo rd + li ke  
boundary_marker="lr"

# The token used to mark the subword boundary. It can be any sign given that it's not a part of the language.
sw_separator="+"

# Path to a normalized text corpus. It will be used to train the subword tokenizer and the language model.  
text_corpus=../demo_data/text_corpus

. ./cmd.sh
. ./path.sh
. utils/parse_options.sh

tag="${method}_${sw_count}_${boundary_marker}"

data=data
exp=exp
log=logs

# Path to store subword tokenization models
model_dir=$data/local/models

# Path to store subword tokenined text corpus
corpus_dir=$data/corpora

mkdir -p $data $exp $log/$method $model_dir $corpus_dir/$method

# Path to the subword-kaldi tool needed to create the L.fst.
# git clone https://github.com/aalto-speech/subword-kaldi.git to your desired location
subword_tools=../../../tools/subword-kaldi/local


if [ $create_venv == true ]; then
  # Any python version over 3.5 should work
  echo "Create a virtual python 3 environment"
  virtualenv -p python3.7 venv
  source venv/bin/activate
  pip install -r requirements.txt
  deactivate
fi 

if [ $stage -le 0 ]; then
echo ============================================================================
echo "               Training a subword tokenization mdoel for ${tag}   "
echo ============================================================================
  # In this section the subword tokenizer is trained. This can be one of four possible
  # methods. There are two implemations of Byte pair encoding. One that uses scripts that
  # are within Kaldi and another that is part of Google's Sentence Piece (sp). The SP package
  # also has an implemation of the Unigram tokenizer. The fourth option is Morfessor. 


  # Note: If you have dencent sized corpus > 4 million sentences, do create a subset  of that
  # corpus for this section and replace the input "$text_corpus" with that subset.
  # e.g. "shuf $text_corpus | head -n 4000000 > $corpus_dir/base_subset_4m
  # This limit is hard coded into the configs for the SP models.
  if [[ $method == 'bpe' ]]; then
    $train_cmd "$log/$method/${tag}_train.log" \
      local/sw_methods/bpe/learn_bpe.py -i $text_corpus \
        -s $sw_count \
        -o $model_dir/${tag}_pair_codes

  elif [[ $method == 'unigram' || $method == 'sp_bpe' ]]; then
    $train_cmd --mem 15G "$log/$method/${tag}_learn.log" \
        local/sw_methods/sp/train_sp.py -i $text_corpus \
            -v $sw_count \
            -t $method \
            -o $model_dir/$tag \

  elif [[ $method == 'morfessor' ]]; then
      echo "To do"
  fi
fi

if [ $stage -le 1 ]; then
echo ============================================================================
echo "               Subword tokeninzing text corpus with ${tag}        "
echo ============================================================================
  if [[ $method == 'bpe' ]]; then
    $train_cmd "$log/$method/${tag}_apply.log" \
      local/sw_methods/bpe/apply_bpe.py -i $text_corpus \
        --codes $model_dir/${tag}_pair_codes \
        -s $sw_separator \
        -o $corpus_dir/$method/${tag}_tmp

    echo "The boundary marker is r and is being changed to ${boundary_marker}"
    if [[ $boundary_marker == r ]]; then
      mv $corpus_dir/$method/${tag}_tmp $corpus_dir/$method/$tag
    else 
      local/sw_methods/change_boundary_marking_style.py $corpus_dir/$method/${tag}_tmp \
        $boundary_marker \
        $sw_separator \
        > $corpus_dir/$method/$tag
        rm $corpus_dir/$method/${tag}_tmp
    fi
    
  elif [[ $method == 'unigram' || $method == 'sp_bpe' ]]; then
    $train_cmd --mem 6G "$log/$method/${tag}_applying.log" \
      local/sw_methods/sp/apply_sp.py -i $text_corpus \
        -m $model_dir/$tag \
        -bm $boundary_marker \
        -o $corpus_dir/$method/$tag

  elif [[ $method == 'morfessor' ]]; then
    echo "To do"

  fi
fi


if [ $stage -le 2 ]; then
echo ============================================================================
echo "               Prepare dict directory for ${tag}        "
echo ============================================================================

  local/prepare_dict.sh $corpus_dir/$method/$tag \
    $data/local/tmp/$tag \
    $data/dict/$tag \
    > "$log/$method/${tag}_dict.log"  2>&1 
fi

if [ $stage -le 3 ]; then
echo ============================================================================
echo "               Prepare lang for ${tag}     "
echo ============================================================================

  (
    if [[ $boundary_marker == 'wb' ]]; then
        extra=3
    else
        extra=1
    fi

    utils/prepare_lang.sh --phone-symbol-table $data/lang/base/phones.txt \
      --num-extra-phone-disambig-syms $extra \
      $data/dict/$tag \
      "<UNK>" \
      $data/local/tmp/$tag \
      $data/lang/$tag

    dir=$data/lang/$tag
    tmpdir=$data/local/tmp/$tag

    # Overwrite L_disambig.fst
    $subword_tools/make_lfst_${boundary_marker}.py $(tail -n$extra $dir/phones/disambig.txt) < $tmpdir/lexiconp_disambig.txt | \
      fstcompile --isymbols=$dir/phones.txt \
        --osymbols=$dir/words.txt \
        --keep_isymbols=false \
        --keep_osymbols=false | \
          fstaddselfloops $dir/phones/wdisambig_phones.int \
            $dir/phones/wdisambig_words.int | \
              fstarcsort --sort_type=olabel > $dir/L_disambig.fst         
    ) > "$log/$method/${tag}_lang.log"  2>&1
fi

if [ $stage -le 4 ]; then
echo ============================================================================
echo "               Create lanuage model for ${tag}        "
echo ============================================================================
    
    # Decoding LM 
    lm_order=6
    $train_cmd --mem 30G "$log/$method/${tag}_lm_${lm_order}g.log" \
        local/lm/make_LM.sh \
            --stage 0 \
            --order $lm_order \
            --pruning "0 10" \
            --carpa false \
            $corpus_dir/$method/$tag \
            $data/lang/$tag \
            $data/dict/$tag/lexicon.txt \
            $data/lm/${tag}_${lm_order}g
    
    # Rescoring LM
    lm_order=8
    $train_cmd --mem 30G "$log/$method/${tag}_lm_${lm_order}g_rescoring.log" \
        local/lm/make_LM.sh \
            --order $lm_order \
            --pruning "0" \
            --carpa true \
            $corpus_dir/bpe/$tag \
            $data/lang/${tag}_8g \
            $data/dict/$tag/lexicon.txt \
            $data/lm/${tag}_${lm_order}g_rescoring \
            > "$log/$method/${tag}_lm_${lm_order}g_rescoring.log"
fi

if [ $stage -le 5 ]; then
echo ============================================================================
echo "               Decoding for ${tag}       "
echo ============================================================================
  

  run/tdnn_decode.sh --stage 0 \
      --decoding-lang $data/lm/${tag}_${lm_order}g \
      --rescoring-lang $data/lm/${tag}_${lm_order}g_rescoring \
      --langdir $data/lang/$tag \
      --exp $exp \
      --boundary-marker $boundary_marker \
      $data/test \
      > $log/$method/${tag}_decode.log 2>&1
fi
