#!/bin/bash -e
#
# Author: Inga Run Helgadottir (Reykjavik University)
# 2020

# Extract, clean and normalize texts from the Icelandic gigaword corpus for language model training

set -o pipefail

stage=0

. ./path.sh
. ./cmd.sh
. ./utils/parse_options.sh || exit 1;
. ./local/utils.sh
. ./local/array.sh

if [ "$1" == "-h" ]; then
    echo "Prepares audio and language data, extract features, train, and test"
    echo "a tdnn-lstm model with Kaldi-ASR."
    echo "Usage: $(basename $0) [-h]"
    exit 0
fi

if [ $# -lt 2 ]; then
    echo "This script extracts, cleans and normalizes texts from"
    echo "the Icelandic Gigaword corpus for language model training"
    echo ""
    echo "Usage: $0 [options] <rmh-corpus-dir> <output-dir>"
    echo " e.g.: $0 /data/risamalheild asr_project/data/lm_trainingdata"
    echo ""
    echo "Options:"
    echo "    --stage         # Stage to run from (default: 0)"
    exit 1;
fi

rmh_corpus=$1
outdir=$2
datadir=/work/inga/data/rmh # $outdir/rmh_text
normdir=$outdir/../norm
mkdir -p $datadir $normdir

if [ $stage -le 1 ]; then
    # Re-write rmh.ipynb to something like extract_rmh_text.py
    # Change the code to work with the default structure of the corpus after downloading
    python3 extract_rmh_text.py "$rmh_corpus" "$datadir"
fi

if [ $stage -le 2 ]; then
    
    echo "Clean each text source"
    
    # Get rid of Latex equations before cleaning
    mv "$datadir"/visindavefur.txt "$datadir"/visindavefur.orig
    sed -r '/\$/d' "$datadir"/visindavefur.orig > "$datadir"/visindavefur.txt
    
    for f in "$datadir"/*/*.txt; do
        (
            name=$(basename "$f")
            utils/slurm.pl --mem 4G "$outdir"/log/clean_text_"${name%.*}".log \
            local/clean_text.sh "$f" "$outdir"/"$name"
        ) &
    done
    wait
    sed -ir 's/\b([0-9]) til ([0-9])\b/\1 \2/g' "$outdir"/fotbolti.txt
    sed -ir 's/\b([0-9]) til ([0-9])\b/\1 \2/g' "$outdir"/433.txt
    
    # Maybe I will switch all of this out for Textahaukur so I just put this temporary solution here for sport scores
    # and remove lines with football player salaries
    # I would anyway have wanted to put this into Thrax grammar if that is what we would use
    
    for f in 433 dfs dv_is eyjan fjardarpostur fotbolti frettabladid_is mbl ruv skessuhorn sunnlenska vf visir; do
        (
            sed -re 's/\b((stór|sigur|sigr|tap|töp|vann|unnu|heima|úti|velli|jafntefli|forystu|/|leikhluta)[^ ]*|jöfn|yfir|undir) ?,? ([0-9]+) til ([0-9]+)\b/\1 \3 \4/g' \
            -e 's/\b((hálfleik|staðan|leikhluta)( var)?|lokatölur( urðu| voru)?|stig|jafnaði|leiddi|forskoti|komu?st í|endaði) ?,? ([0-9]+) til ([0-9]+)\b/\1 \5 \6/g' \
            -e 's/\b([0-9]+) til ([0-9]+) ?,? (sigur|sigri|tap|tapi|á heima|á úti|jafntefli|forystu|yfir|undir|í hálfleik)\b/\1 \2 \3/g' \
            -e 's/\b(aftureldingu?|ármanni?|breiðablik|dalvík \/ reynir?|einherj[ai]|f h|fjölnir?|fylkir?|grótt[au]|haukar?|haukum|ham[ar][ri]|h k|hvíti riddarinn|hvíta riddaran[nu]m?|höttu?r?|hetti|í r|í a|í b v|leiknir?[ r]?|keflavík|k a|k v|k r|reynir?[ s]?|selfoss|sindr[ia]|skallagrímu?r?|snæfelli?|stjarnan|stjörnun[an]i?|tindastóll?i?|grindavík|njarðvík|valur|víkingi?u?r?[ ó]?|völsungi?u?r?|þór ak|þór þ|þróttu?r?[ r]?) ?,? ([0-9]{1,2}) til ([0-9]{1,2})\b/\1 \2 \3/g' \
            -e 's/\b([0-9]+) til ([0-9]+) *$/\1 \2/' \
            -e '/[$£€¥] ?[0-9]/d' "$outdir"/"$f".txt > "$outdir"/"$f".sport
        ) &
    done
    
    for f in frettatiminn_bl frettatiminn morgunbladid pressan ras1_og_2 sjonvarpid stod2 vf_kylfingur; do
        # Simpler version of regex
        (
            sed -re 's/\b((stór|sigur|sigr|tap|töp|vann|unnu|velli|jafntefli|forystu|hálfleik)[^ ]*) ?,? ([0-9]+) til ([0-9]+)\b/\1 \3 \4/g' \
            -e 's/\b([0-9]+) til ([0-9]+) ?,? (sigur|sigri|tap|tapi|á heimavelli|á útivelli|jafntefli|forystu|í hálfleik)\b/\1 \2 \3/g' \
            -e 's/\b((hálfleik|staðan|leikhluta)( var)?|lokatölur( urðu| voru)?|stig|leiddi|forskoti|komu?st í|endaði) ?,? ([0-9]+) til ([0-9]+)\b/\1 \5 \6/g' \
            < "$outdir"/"$f".txt > "$outdir"/"$f".sport
        ) &
    done
    wait
    
    for f in "$outdir"/*.sport; do
        name=$(basename "$f")
        mv "$f" "$outdir"/"${name%.*}".txt
    done
    
    for f in "$outdir"/*.txt; do
        (
            name=$(basename "$f")
            sed -re 's/([$£€¥])/ \1 /g' -e 's/([$£€¥]) ([0-9]+( komma( [0-9])+)?( millj[^ ]*| þúsund[^ ]*)?)/\2 \1/g' -e 's:([0-9]+),([0-46-9]):\1 komma \2:g' -e 's:([0-9]+),5([0-9]):\1 komma 5\2:g' \
            < "$f" \
            | perl -pe 's/ (0(?!,5))/ $1 /g' | perl -pe 's/komma (0? ?)(\d)(\d)(\d)(\d?)/komma $1$2 $3 $4 $5/g' \
            | sed -re 's:([0-9]+)\.([0-9]{3})\b\.?:\1\2:g' -e 's: *%:% :g' -e 's/ +/ /g' \
            > "$outdir"/"${name%.*}".currency
        ) &
    done
    wait
    
    for f in "$outdir"/*.currency; do
        name=$(basename "$f")
        mv "$f" "$outdir"/"${name%.*}".txt
    done
    
fi

if [ $stage -le 3 ]; then
    echo 'Create an expansion langugage model'
    # Get a wordlist to add to the expansion model
    cat "$outdir"/*.txt | tr ' ' '\n' | grep -Ev '[^a-záðéíóúýþæö]' | sort | uniq -c > "$outdir"/intermediate/wordlist_rmh.cnt
    # Keep words appearing 15 or more times
    awk '$2 ~ /[[:print:]]/ { if($1 > 15) print $2 }' "$outdir"/intermediate/wordlist_rmh.cnt > "$outdir"/intermediate/wordlist_rmh_15occ.txt
    # Data from Helga
    tr ' ' '\n' < "$normdir"/helga_normalization_no_numbers.txt | sort -u > "$normdir"/wordlist_helga.txt
    
    utils/slurm.pl --mem 4G "$outdir"/log/make_expansion_lm.log \
    local/make_expansion_lm.sh "$outdir"/intermediate/wordlist_rmh_15occ.txt "$normdir"
fi


if [ $stage -le 4 ]; then
    echo 'Expand abbreviations and numbers'
    # NOTE! ras2.txt only contains 26 lines and should not be split up at all
    for f in "$outdir"/*.txt; do
        (
            name=$(basename "$f")
            utils/slurm.pl --mem 4G "$outdir"/log/expand_text_"${name%.*}".log \
            local/expand_big.sh "$f"
        )
    done
    #"$outdir"/"${name%.*}"_expanded
    
    # NOTE! Need to modify probably based on how I deal with uttIDs and
    # what symbols other than letters are allowed in the final text
    echo "Make a language model training text from the expanded text"
    cat "$outdir"/*_expanded.txt \
    | sed -re 's: *[.:?!]+ *$::g' -e 's: *[.:?!]+ :\n:g' \
    -e 's:[^A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö \n]: :g' \
    -e 's: +: :g' \
    > "$outdir"/rmh_"$(date +'%Y-%m-%d')".txt || exit 1;
    
fi

exit 0