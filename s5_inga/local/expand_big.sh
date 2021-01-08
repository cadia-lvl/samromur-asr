#!/bin/bash -e

# Copyright 2017  Reykjavik University (Author: Inga Rún Helgadóttir)
# Apache 2.0

# Expand abbreviations and numbers in big text sets.
# Assume local/prep_expansionLM_training_subset_Leipzig.sh has been run.
# There a base training set is created.
# The results from it are used as partial input here,
# but the fsts obtained there are the ones used for expansion in expand_small.sh

set -o pipefail

nj=64
stage=-1
order=4
lc=_lc

echo "$0 $*"  # Print the command line for logging

#expLMbase=$root_expansionLM_cs_data

. ./cmd.sh
. ./path.sh
. utils/parse_options.sh
. local/utils.sh

# Maybe I should rather have these just in the same dir as the input/output text since it is only used for that

# if [ $# != 2 ]; then
#     echo "Text normalize training corpora, i.e. expand numbers and abbreviations,"
#     echo "using an expansion language model which is adapted to the training corpora."
#     echo ""
#     echo "Usage: local/expand.sh [options] <input-text-file> <output-text-file>"
#     echo "e.g.: local/expand.sh data/all/text_bb_SpellingFixed.txt data/all/text"
#     exit 1;
# fi

infile=$1
#outfile=$2
normdir=/work/inga/h7/data/norm #$3
dir=$(dirname "$infile");
name=$(basename "$infile")
#expLM=$dir/expLM
mkdir -p "$dir"/{log,split"${nj}"_"${name%.*}"}

for f in $infile "$normdir"/EXPAND_UTT_lc.fst; do
    [ ! -f "$f" ] && echo "$0: expected $f to exist" && exit 1;
done
#$expLMbase/{wordlist_numbertexts_althingi100.txt,numbertexts_althingi100.txt.gz}

# if [ $stage -le 1 ]; then

#     utils/slurm.pl --mem 12G "$dir"/log/make_adapted_expansionLM.log local/make_adapted_expansionLM.sh --order $order $infile "$normdir" $expLMbase $expLM

# fi

if [ $stage -le 2 ]; then
    echo "We want to process it in parallel."
    #NOTE! Don't put "" around $split_text or it will be taken as a single name
    IFS=$' \t\n'
    split_text=$(for j in `seq 1 $nj`; do printf "$dir/split%s_${name%.*}/text.%s.txt " "$nj" "$j"; done)
    # I need to add IDs to get the utterances on a Kaldi format
    awk '{printf("%010d %s\n", NR, $0)}' "$infile" > "${dir}"/"${name%.*}"_wID.txt
    utils/split_scp.pl "${dir}"/"${name%.*}"_wID.txt $split_text
fi

if [ $stage -le 3 ]; then
    echo "Expand"
    utils/slurm.pl --mem 4G JOB=1:$nj "${dir}"/log/expand-numbers_"${name%.*}".JOB.log \
    expand-numbers --word-symbol-table=${normdir}/expLM_words$lc.txt \
    ark,t:"${dir}"/split${nj}_"${name%.*}"/text.JOB.txt \
    ${normdir}/expand_to_words$lc.fst ${normdir}/expansionLM_${order}g$lc.fst \
    ark,t:"${dir}"/split${nj}_"${name%.*}"/text_expanded_${order}g.JOB.txt
fi


if [ $stage -le 4 ]; then
    
    echo "Check if all the speeches were expanded"
    join -1 1 -2 1 <(grep -E "^[0-9]{10} *$" "${dir}"/split${nj}_"${name%.*}"/text_expanded_${order}g.*.txt | sed 's/ *//g' | cut -d':' -f2 | sort) \
    <(sort "$dir"/split${nj}_"${name%.*}"/text.*.txt) > "$dir"/split${nj}_"${name%.*}"/text_notexpanded_${order}g.txt
    # Ignore lines which were not expanded
    grep -vFf <(cut -d" " -f1 "$dir"/split${nj}_"${name%.*}"/text_notexpanded_${order}g.txt) \
    <(sort -u "$dir"/split${nj}_"${name%.*}"/text_expanded_${order}g.*.txt) | sort -n \
    | cut -d" " -f2- > "$dir"/"${name%.*}"_expanded.txt
    
    # if [[ -s "$dir"/split${nj}_"${name%.*}"/text_notexpanded_${order}g.txt ]]; then
    #     n=$(< "$dir"/split${nj}_"${name%.*}"/text_notexpanded_${order}g.txt wc -l)
    #     printf "%s lines were empty after expansion\n" "$n"
    #     echo "they can be viewed in $dir/split${nj}_${name%.*}/text_notexpanded_${order}g.txt"
    #     exit 1;
    # else
    #     echo "All speeches were expanded :)"
    #     # If LM utterances then I remove the uttIDs
    #     if grep -Eq "^[0-9]{10}" "$dir"/text_expanded_${order}g.txt; then
    #         cut -d" " -f2- "$dir"/text_expanded_${order}g.txt \
    #         > "$dir"/tmp && mv "$dir"/tmp "$dir"/text_expanded_${order}g.txt
    #     fi
    # fi
fi

# if [ $stage -le 5 ]; then

#     if [ -e "${outfile}" ] ; then
#         # we don't want to overwrite old stuff, ask the user to delete it.
#         echo "$0: ${outfile} already exists: "
#         echo "Are you sure you want to proceed?"
#         echo "It will overwrite the file"
#         echo ""
#         echo "  If so, please delete and then rerun this part"
#         exit 1;
#     else
#         cp "$dir"/text_expanded_${order}g.txt "$outfile"
#     fi
# fi

exit 0;

