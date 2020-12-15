#!/bin/bash -e

set -o pipefail

# This script cleans up text, which can later be processed further to be used in AMs and LMs

stage=-1
lex_ext=txt

. ./path.sh
. parse_options.sh || exit 1;
. ./local/utils.sh
. ./local/array.sh

if [ $# != 2 ]; then
    echo "Usage: local/clean_text.sh [options] <input-text> <output-text>"
    echo "a --stage option can be given to not run the whole script"
    exit 1;
fi

textin=$1; shift
textout=$1; shift
outdir=$(dirname "$textout")
intermediate="$outdir"/intermediate
mkdir -p "$outdir"/{intermediate,log}
name=$(basename "$textin")

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

cut -f1 "$root_thraxgrammar_lex"/abbr_lexicon.$lex_ext | tr " " "\n" | sort -u > "$tmp"/abbr_list
cut -f2 "$root_thraxgrammar_lex"/acro_denormalize.$lex_ext > "$tmp"/abbr_acro_as_letters
#cut -f2 "$root_thraxgrammar_lex"/ambiguous_personal_names.$lex_ext > "$tmp"/ambiguous_names

for f in "$textin" "$tmp"/abbr_list "$tmp"/abbr_acro_as_letters ; do
    [ ! -f "$f" ] && echo "$0: expected $f to exist" && exit 1;
done

# Make a regex pattern of all abbreviations, upper and lower case.
cat "$tmp"/abbr_list <(sed -r 's:.*:\u&:' "$tmp"/abbr_list) \
| sort -u | tr "\n" "|" | sed '$s/|$//' \
| perl -pe "s:\|:\\\b\|\\\b:g" \
> "$tmp"/abbr_pattern.tmp || error 1 $LINENO "Failed creating pattern of abbreviations";

if [ $stage -le 1 ]; then
    echo "Remove duplicates"
    awk '!x[$0]++' "$textin" > "$intermediate"/"${name%.*}"_uniq.txt
fi

if [ $stage -le 2 ]; then
    echo "Clean the data by removing and rewriting lines using sed regex"
    # 1. Remove …„“”\"|«»‘*_<>●,, and trailing spaces
    # 2. Remove lines containing ^, ¦, https (usually a long url follows)
    #        or end with [ . or www ., and remove lines conaining three periods,
    #        used to denote that the transcriber did not hear what was said, strange sentences often
    # 3. Remove content in parentheses and brackets
    # 4. Remove remaining parentheses, used in lists, e.g. a) bla, b) bla bla?
    #         and remove remaining lines with (), [], {}
    # 5. Rewrite simple urls, e.g. www.mbl.is and Vísir.is
    # 6. Rewrite e-mail addresses, e.g. abc@abc.is -> abc @ abc punktur is
    # 7. Rewrite social media @ and #
    # 7. Rewrite dash and hyphens to "til" if between numbers or e.g. 2. apríl - 4. maí
    # 8. Remove dash or hyphens if sandwitched between words e.g. Slysavarnarfélagið-Landsbjörg and before "og", "eða" and "né"
    # 9. Change en dash to a hyphen
    # 10. Remove hyphen after [;:,] and deal with multiple punctuation after words/numbers
    # 11. Remove symbols other than letters or numbers at line beginnings
    # 12. Remove lines which don't contain letters and change to one space between words.
    sed -re 's:[…„“”\"\|«»‘*<>●]::g' -e 's: ,, |_: :g' -e 's: +$::' \
    -e '/\^|¦|https|\[ \.$|www \.$|\.\.\./d' \
    -e 's:\(+[^)]*?\)+: :g' -e 's:\[[^]]*?\]: :g' \
    -e 's:(^| )(.{1,2}) \) :\1\2 :g' -e '/\[|\]|\{|\}|\(|\)/d' \
    -e 's:www\.([^\.]+).([^ ]+) :w w w \1 punktur \2 :g' -e 's:\.(is|com|net|org|edu|int|dk|co|no|se|fi|de)\b: punktur \1:g' \
    -e 's:\@([^\.]+).([^ ]+): hjá \1 punktur \2:g' \
    -e 's:\@:hjá :g' -e 's/(merki[^ ]*|hashtag[^ ]*) #/\1 /g' \
    -e 's:([0-9\.%]+)( ([a-záðéíóúýþæö]+ )?)[–-] ([0-9]):\1\2til \4:g' \
    -e 's:[–-]([^ ]): \1:g' -e 's: - (og|né|eða) : \1 :g' \
    -e 's:–:-:g' \
    -e 's/([;:,]) -/\1/g' -e 's:([^ .,:;?!-]+) ([.,:;?! -]+)([.,:;?!-]):\1 \3:g' \
    -e 's:^[^A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö0-9]+::' \
    -e '/^[^A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]*$/d' -e 's/ +/ /g' \
    < "$intermediate"/"${name%.*}"_uniq.txt > "$intermediate"/"${name%.*}"_cleaned1.txt
fi


if [ $stage -le 3 ]; then
    
    echo "Rewrite and remove punctuations"
    # 1) Rewrite fractions
    # 2) Rewrite law numbers
    # 3) Rewrite time,
    # 4) Remove punctuations which is safe to remove
    # 5) Add space around currency symbols
    # 6) Remove commas used as quotation marks, remove or change "..." -> "."
    # 7) Deal with double punctuation after words/numbers
    # 8) Remove "ja" from numbers written like "22ja" and fix some incorrectly written units (in case manually written),
    # 9) In an itemized list, lowercase what comes after the numbering.
    # 10-11) Rewrite decimals, f.ex "0,045" to "0 komma 0 45" and "0,00345" to "0 komma 0 0 3 4 5" and remove space before a "%",
    # 12) Rewrite vulgar fractions
    # 13) Remove the period in abbreviated middle names
    # 14) Remove periods inside abbreviation
    # 15) Remove the abbreviation periods
    # 16) Rewrite thousands and millions, f.ex. 3.500 to 3500,
    # 17) Rewrite chapter and clause numbers and time and remove remaining periods between numbers, f.ex. "ákvæði 2.1.3" to "ákvæði 2 1 3" and "kl 15.30" to "kl 15 30",
    # 18-19) Add spaces between letters or currency symbols and numbers (Example:1st: "4x4", 2nd: f.ex. "bla.3. júlí", 3rd: "1.-bekk."
    # 20) Fix spacing around % and degrees celsius and add space in a number starting with a zero
    sed -re 's:([0-9]) 1/2\b:\1,5:g' -e 's:\b([0-9])/([0-9]{1,2})\b:\1 \2\.:g' \
    -e 's:/?([0-9]+)/([0-9]+): \1 \2:g' -e 's:([0-9]+)/([A-Z]{2,}):\1 \2:g' -e 's:([0-9])/ ([0-9]):\1 \2:g' \
    -e 's/([0-9]):([0-9][0-9])/\1 \2/g' \
    -e 's:[^a-záðéíóúýþæöA-ZÁÉÍÓÚÝÞÆÖ0-9 \.,?!:;/#$£€¥%‰°º—–²³¼¾½ _-]+::g' -e 's: |__+: :g' \
    -e 's/([$£€¥])/ \1 /g' -e 's/([$£€¥]) ([0-9,.]+( millj[^ ]*| þúsund[^ ]*)?)/\2 \1/g'\
    -e 's: ,,: :g' -e 's:\.\.+ ([A-ZÁÐÉÍÓÚÝÞÆÖ]):. \1:g' -e 's:\.\.+::g' \
    -e 's:([0-9]+)ja\b:\1:g' -e 's:([ck]?m)2: \1²:g' -e 's:([ck]?m)3: \1³:g' -e 's: ([kgmt])[wV] : \1W :g' -e 's:Wst:\L&:g' \
    -e 's:\b([0-9]\.) +([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \l\2:g' \
    -e 's:([0-9]+),([0-46-9]):\1 komma \2:g' -e 's:([0-9]+),5([0-9]):\1 komma 5\2:g' \
    < "$intermediate"/"${name%.*}"_cleaned1.txt \
    | perl -pe 's/ (0(?!,5))/ $1 /g' | perl -pe 's/komma (0? ?)(\d)(\d)(\d)(\d?)/komma $1$2 $3 $4 $5/g' \
    | sed -re 's:¼: einn 4. :g' -e 's:¾: 3 fjórðu:g' -e 's:([0-9])½:\1,5 :g' -e 's: ½: 0,5 :g' \
    -e 's:([A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]+) ([A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]?)\. ([A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]+):\1 \2 \3:g' \
    -e 's:[ /]([ck]?m[²³]?|[km]g|[kmgt]?w|gr|umr|sl|millj|nk|mgr|kr|osfrv)([.:?!]+) +([A-ZÁÐÉÍÓÚÝÞÆÖ]): \1 \2 \l\3:g' \
    -e 's:\.([a-záðéíóúýþæö]):\1:g' \
    -e "s:(\b$(cat $tmp/abbr_pattern.tmp))\.:\1:g" \
    -e 's:([0-9]+)\.([0-9]{3})\b\.?:\1\2:g' \
    -e 's:([0-9]{1,2})\.([0-9]{1,2})\b:\1 \2:g' -e 's:([0-9]{1,2})\.([0-9]{1,2})\b\.?:\1 \2 :g' \
    -e 's:\b([0-9]+)([^0-9 ,.])([0-9]):\1 \2 \3:g' -e 's:\b([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]+)\.?-?([0-9]+)\b:\1 \2:g' \
    -e 's:\b([0-9,]+%?\.?)-?([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]+)\b:\1 \2:g' \
    -e 's: *%:% :g' -e 's:([°º]) c :°c :g' -e 's: 0([0-9]): 0 \1:g' \
    > "$intermediate"/"${name%.*}"_cleaned2.txt || error 13 $LINENO "${error_array[13]}";
    
fi

if [ $stage -le 3 ]; then
    echo "Expand some abbreviations which don't have cases."
    echo "Remove the periods from the rest"
    sed -re 's:\ba\.m\.k ?\.:að minnsta kosti:g' \
    -e 's:\bág ?\.:ágúst:g' \
    -e 's:\bdes ?\.:desember:g' \
    -e 's:\bdr ?\.:doktor:g' \
    -e 's:\be\.t\.v ?\.:ef til vill:g' \
    -e 's:\bfeb ?\.:febrúar:g' \
    -e 's:\bfrh ?\.:framhald:g' \
    -e 's:\bfyrrv ?\.:fyrrverandi:g' \
    -e 's:\bheilbrrh ?\.:heilbrigðisráðherra:g' \
    -e 's:\biðnrh ?\.:iðnaðarráðherra:g' \
    -e 's:\binnanrrh ?\.:innanríkisráðherra:g' \
    -e 's:\bjan\.:janúar:g' \
    -e 's:\bkl ?\.:klukkan:g' \
    -e 's:\blandbrh ?\.:landbúnaðarráðherra:g' \
    -e 's:\bm\.a\.s ?\.:meira að segja:g' \
    -e 's:\bm\.a ?\.:meðal annars:g' \
    -e 's:\bmenntmrh ?\.:mennta og menningarmálaráðherra:g' \
    -e 's:\bm ?\.kr ?\.:millj kr:g' \
    -e 's:\bnk ?\.:næstkomandi:g' \
    -e 's:\bnóv ?\.:nóvember:g' \
    -e 's:\bnr ?\.:númer:g' \
    -e 's:\bnúv ?\.:núverandi:g' \
    -e 's:\bokt ?\.:október:g' \
    -e 's:\bo\.s\.frv ?\.:og svo framvegis:g' \
    -e 's:\bo\.þ\.h ?\.:og þess háttar:g' \
    -e 's:\bpr ?\.:per:g' \
    -e 's:\bsbr ?\.:samanber:g' \
    -e 's:\bsept ?\.:september:g' \
    -e 's:\bskv ?\.:samkvæmt:g' \
    -e 's:\bs\.s ?\.:svo sem:g' \
    -e 's:\bstk ?\.:stykki:g' \
    -e 's:\bt\.d ?\.:til dæmis:g' \
    -e 's:\bt\.a\.m ?\.:til að mynda:g' \
    -e 's:\bu\.þ\.b ?\.:um það bil:g' \
    -e 's:\butanrrh ?\.:utanríkisráðherra:g' \
    -e 's:\bviðskrh ?\.:viðskiptaráðherra:g' \
    -e 's:\bþáv ?\.:þáverandi:g' \
    -e 's:\b/þ\.e ?\.:það er:g' \
    -e 's:\bþús ?\.:þúsund:g' \
    -e 's:\bþ\.e\.a\.s ?\.:það er að segja:g' \
    -e 's:([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö])\.:\1:g' \
    < "$intermediate"/"${name%.*}"_cleaned2.txt \
    > "$intermediate"/"${name%.*}"_abbrexp.txt
fi



if [ $stage -le 3 ]; then
    
    # Add spaces into acronyms pronounced as letters
    if grep -E -q "[A-ZÁÐÉÍÓÚÝÞÆÖ]{2,}\b" "$intermediate"/"${name%.*}"_abbrexp.txt ; then
        grep -E -o "[A-ZÁÐÉÍÓÚÝÞÆÖ]{2,}\b" \
        < "$intermediate"/"${name%.*}"_abbrexp.txt  \
        > "$tmp"/acro.tmp || error 14 $LINENO "${error_array[14]}";
        
        if grep -E -q "\b[AÁEÉIÍOÓUÚYÝÆÖ]+\b|\b[QWRTPÐSDFGHJKLZXCVBNM]+\b" "$tmp"/acro.tmp; then
            grep -E "\b[AÁEÉIÍOÓUÚYÝÆÖ]+\b|\b[QWRTPÐSDFGHJKLZXCVBNM]+\b" \
            < "$tmp"/acro.tmp > "$tmp"/asletters.tmp || error 14 $LINENO "${error_array[14]}";
            
            cat "$tmp"/asletters.tmp "$tmp"/abbr_acro_as_letters \
            | sort -u > "$tmp"/asletters_tot.tmp || error 14 $LINENO "${error_array[14]}";
        else
            cp "$tmp"/abbr_acro_as_letters "$tmp"/asletters_tot.tmp || error 14 $LINENO "${error_array[14]}";
        fi
    else
        cp "$tmp"/abbr_acro_as_letters "$tmp"/asletters_tot.tmp || error 14 $LINENO "${error_array[14]}";
    fi
    
    # Create a table where the 1st col is the acronym and the 2nd one is the acronym with with spaces between the letters
    paste <(awk '{ print length, $0 }' "$tmp"/asletters_tot.tmp \
    | sort -nrs | cut -d" " -f2) \
    <(awk '{ print length, $0 }' "$tmp"/asletters_tot.tmp \
    | sort -nrs | cut -d" " -f2 | sed -re 's/./\l& /g' -e 's/ +$//') \
    | tr '\t' ' ' | sed -re 's: +: :g' \
    > "$tmp"/insert_space_into_acro.tmp || error 14 $LINENO "${error_array[14]}";
    
    # Create a sed pattern file: Change the first space to ":"
    sed -re 's/ /\\b:/' -e 's/^.*/s:\\b&/' -e 's/$/:g/g' \
    < "$tmp"/insert_space_into_acro.tmp \
    > "$tmp"/acro_sed_pattern.tmp || error 13 $LINENO "${error_array[13]}";
    
    /bin/sed -f "$tmp"/acro_sed_pattern.tmp "$intermediate"/"${name%.*}"_abbrexp.txt \
    > "$intermediate"/"${name%.*}"_exp2.txt || error 13 $LINENO "${error_array[13]}";
    
    # Lowercase the text
    sed -r 's/^.*/\L&/g' "$intermediate"/"${name%.*}"_exp2.txt > "$textout"
fi

exit 0;