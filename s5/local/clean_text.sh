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

tmp=$(mktemp -d)
cleanup () {
    rm -rf "$tmp"
}
trap cleanup EXIT

prondict=$(ls -t "$root_lexicon"/prondict.* | head -n1)
bad_words=$(ls -t "$root_listdir"/discouraged_words.* | head -n1)
cut -f1 "$root_thraxgrammar_lex"/abbr_lexicon.$lex_ext | tr " " "\n" | sort -u > "$tmp"/abbr_list
cut -f2 "$root_thraxgrammar_lex"/acro_denormalize.$lex_ext > "$tmp"/abbr_acro_as_letters
cut -f2 "$root_thraxgrammar_lex"/ambiguous_personal_names.$lex_ext > "$tmp"/ambiguous_names

for f in "$textin" "$prondict" "$tmp"/abbr_list "$tmp"/abbr_acro_as_letters "$tmp"/ambiguous_names; do
    [ ! -f "$f" ] && echo "$0: expected $f to exist" && exit 1;
done

# Make a regex pattern of all abbreviations, upper and lower case.
cat "$tmp"/abbr_list <(sed -r 's:.*:\u&:' "$tmp"/abbr_list) \
| sort -u | tr "\n" "|" | sed '$s/|$//' \
| perl -pe "s:\|:\\\b\|\\\b:g" \
> "$tmp"/abbr_pattern.tmp || error 1 $LINENO "Failed creating pattern of abbreviations";



if [ $stage -le 1 ]; then
    echo "Clean the data by removing and rewriting lines using sed regex"
    # 1. Remove …„“”\"|«»‘*_<>●,, and trailing spaces
    # 2. Remove lines which don't end with a EOS punctuation: [^\.\?\!]$
    # 3. Remove lines containing ^, ¦, https (usually a long url follows)
    #        or end with [ . or www ., and remove lines conaining three periods,
    #        used to denote that the transcriber did not hear what was said, strange sentences often
    # 4. Remove content in parentheses and brackets
    # 5. Remove remaining parentheses, used in lists, e.g. a) bla, b) bla bla?
    #         and remove remaining lines with (), [], {}
    # 6. Rewrite simple urls, e.g. www.mbl.is and Vísir.is
    # 7. Rewrite e-mail addresses, e.g. abc@abc.is -> abc @ abc punktur is
    # 8. Rewrite dash and hyphens to "til" if between numbers or e.g. 2. apríl - 4. maí
    # 9. Remove dash or hyphens if sandwitched between words e.g. Slysavarnarfélagið-Landsbjörg and before "og", "eða" and "né"
    # 10. Change en dash to a hyphen
    # 11. Remove hyphen after [;:,] and deal with multiple punctuation after words/numbers
    # 12. Remove symbols other than letters or numbers at line beginnings
    # 13. Remove lines which don't contain letters and change to one space between words.
    for n in morgunbladid ljosvakamidlar textasafn_arnastofnun; do
        sed -re 's:[…„“”\"\|«»‘*<>●]::g' -e 's: ,, |_: :g' -e 's: +$::' \
        -e '/^.*?[^\.\?\!]$/d' \
        -e '/\^|¦|https|\[ \.$|www \.$|\.\.\./d' \
        -e 's:\(+[^)]*?\)+: :g' -e 's:\[[^]]*?\]: :g' \
        -e 's:(^| )(.{1,2}) \) :\1\2 :g' -e '/\[|\]|\{|\}|\(|\)/d' \
        -e 's:www\.([^\.]+).([^ ]+) :w w w \1 punktur \2 :g' -e 's:\.(is|com|net|org|edu|int|dk|co|no|se|fi|de)\b: punktur \1:g' \
        -e 's:\@([^\.]+).([^ ]+): @ \1 punktur \2:g' \
        -e 's:([0-9\.%]+)( ([a-záðéíóúýþæö]+ )?)[–-] ([0-9]):\1\2til \4:g' \
        -e 's:[–-]([^ ]): \1:g' -e 's: - (og|né|eða) : \1 :g' \
        -e 's:–:-:g' \
        -e 's/([;:,]) -/\1/g' -e 's:([^ .,:;?!-]+) ([.,:;?! -]+)([.,:;?!-]):\1 \3:g' \
        -e 's:^[^A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö0-9]+::' \
        -e '/^[^A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]*$/d' -e 's/ +/ /g' \
        < $textin > $tmp/rmh_${n}_cleaned.txt
    done
fi


if [ $stage -le 2 ]; then
    
    echo "Rewrite and remove punctuations"
    # 1) Rewrite fractions
    # 2) Rewrite law numbers
    # 3) Rewrite time,
    # 6) Remove punctuations which is safe to remove
    # 7) Remove commas used as quotation marks, remove or change "..." -> "."
    # 8) Deal with double punctuation after words/numbers
    # 9) Remove "ja" from numbers written like "22ja" and fix some incorrectly written units (in case manually written),
    # 12) In an itemized list, lowercase what comes after the numbering.
    # 14-15) Rewrite decimals, f.ex "0,045" to "0 komma 0 45" and "0,00345" to "0 komma 0 0 3 4 5" and remove space before a "%",
    # 16) Rewrite vulgar fractions
    # 17) Add space before "," when not followed by a number and before ";"
    # 18) Remove the period in abbreviated middle names
    # 19) For measurement units and a few abbreviations that often stand at the end of sentences, add space before the period
    # 20) Remove periods inside abbreviation
    # 21) Move EOS punctuation away from the word and lowercase the next word, if the previous word is a number or it is the last word.
    # 22) Remove the abbreviation periods
    # 23) Move remaining EOS punctuation away from the word and lowercase next word
    # 24) Lowercase the first word in a speech
    # 25) Rewrite "/a " to "á ári", "/s " to "á sekúndu" and so on.
    # 26) Switch dashes (exept in utt filenames) and remaining slashes out for space
    # 27) Rewrite thousands and millions, f.ex. 3.500 to 3500,
    # 28) Rewrite chapter and clause numbers and time and remove remaining periods between numbers, f.ex. "ákvæði 2.1.3" to "ákvæði 2 1 3" and "kl 15.30" to "kl 15 30",
    # 29) Add spaces between letters and numbers in alpha-numeric words (Example:1st: "4x4", 2nd: f.ex. "bla.3. júlí", 3rd: "1.-bekk."
    # 30) Remove punctuation attached to the word behind
    # 31) Fix spacing around % and degrees celsius and add space in a number starting with a zero
    # 32) Fix if the first letter in an acronym has been lowercased.
    sed -re 's:([0-9]) 1/2\b:\1,5:g' -e 's:\b([0-9])/([0-9]{1,2})\b:\1 \2\.:g' \
    -e 's:/?([0-9]+)/([0-9]+): \1 \2:g' -e 's:([0-9]+)/([A-Z]{2,}):\1 \2:g' -e 's:([0-9])/ ([0-9]):\1 \2:g' \
    -e 's/([0-9]):([0-9][0-9])/\1 \2/g' \
    -e 's:[^a-záðéíóúýþæöA-ZÁÉÍÓÚÝÞÆÖ0-9 \.,?!:;/%‰°º—–²³¼¾½ _-]+::g' -e 's: |__+: :g' \
    -e 's: ,,: :g' -e 's:\.\.+ ([A-ZÁÐÉÍÓÚÝÞÆÖ]):. \1:g' -e 's:\.\.+::g' \
    -e 's:\b([^0-9 .,:;?!]+)([.,:;?!]+)([.,:;?!]):\1 \3 :g' -e 's:\b([0-9]+[.,:;?!])([.,:;?!]):\1 \2 :g' -e 's:\b(,[0-9]+)([.,:;?!]):\1 \2 :g' \
    -e 's:([0-9]+)ja\b:\1:g' -e 's:([ck]?m)2: \1²:g' -e 's:([ck]?m)3: \1³:g' -e 's: ([kgmt])[wV] : \1W :g' -e 's:Wst:\L&:g' \
    -e 's:\b([0-9]\.) +([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \l\2:g' \
    -e 's:([0-9]+),([0-46-9]):\1 komma \2:g' -e 's:([0-9]+),5([0-9]):\1 komma 5\2:g' \
    < "$intermediate"/text_noRoman.txt \
    | perl -pe 's/ (0(?!,5))/ $1 /g' | perl -pe 's/komma (0? ?)(\d)(\d)(\d)(\d?)/komma $1$2 $3 $4 $5/g' \
    | sed -re 's:¼: einn 4. :g' -e 's:¾: 3 fjórðu:g' -e 's:([0-9])½:\1,5 :g' -e 's: ½: 0,5 :g' \
    -e 's:([,;])([^0-9]|\s*$): \1 \2:g' -e 's:([^0-9]),:\1 ,:g' \
    -e 's:([A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]+) ([A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]?)\. ([A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]+):\1 \2 \3:g' \
    -e 's:[ /]([ck]?m[²³]?|[km]g|[kmgt]?w|gr|umr|sl|millj|nk|mgr|kr|osfrv)([.:?!]+) +([A-ZÁÐÉÍÓÚÝÞÆÖ]): \1 \2 \l\3:g' \
    -e 's:\.([a-záðéíóúýþæö]):\1:g' \
    -e 's:([0-9,.]{3,})([.:?!]+) *([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \2 \l\3:g' -e 's:([0-9]%)([.:?!]+) *([A-ZÁÐÉÍÓÚÝÞÆÖ]):\1 \2 \l\3:g' -e 's:([0-9.,]{4,})([.:?!]+) :\1 \2 :g' -e 's:([0-9]%)([.:?!]+) *:\1 \2 :g' -e 's:([.:?!]+)\s*$: \1:g' \
    -e "s:(\b$(cat $tmp/abbr_pattern.tmp))\.:\1:g" \
    -e 's:([.:?!]+) *([A-ZÁÐÉÍÓÚÝÞÆÖ]): \1 \l\2:g' -e 's:([^0-9])([.:?!]+)([0-9]):\1 \2 \3:g' -e 's:([^0-9])([.:?!]+):\1 \2:g' \
    -e 's:(^[^ ]+) ([^ ]+):\1 \l\2:' \
    -e 's:/a\b: á ári:g' -e 's:/s\b: á sekúndu:g' -e 's:/kg\b: á kíló:g' -e 's:/klst\b: á klukkustund:g' \
    -e 's:—|–|/|tilstr[^ 0-9]*?\.?: :g' -e 's:([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö])-+([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]):\1 \2:g' \
    -e 's:([0-9]+)\.([0-9]{3})\b\.?:\1\2:g' \
    -e 's:([0-9]{1,2})\.([0-9]{1,2})\b:\1 \2:g' -e 's:([0-9]{1,2})\.([0-9]{1,2})\b\.?:\1 \2 :g' \
    -e 's:\b([0-9]+)([^0-9 ,.])([0-9]):\1 \2 \3:g' -e 's:\b([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]+)\.?-?([0-9]+)\b:\1 \2:g' -e 's:\b([0-9,]+%?\.?)-?([A-ZÁÐÉÍÓÚÝÞÆÖa-záðéíóúýþæö]+)\b:\1 \2:g' \
    -e 's: ([.,:;?!])([^ ]): \1 \2:g' \
    -e 's: *%:% :g' -e 's:([°º]) c :°c :g' -e 's: 0([0-9]): 0 \1:g' \
    -e 's:\b([a-záðéíóúýþæö][A-ZÁÐÉÍÓÚÝÞÆÖ][^a-záðéíóúýþæö]):\u\1:g' \
    > "$intermediate"/text_noPuncts.txt || error 13 $LINENO "${error_array[13]}";
    
fi

if [ $stage -le 3 ]; then
    echo "Expand some abbreviations which don't have cases."
    echo "Remove the periods from the rest"
    # End with removing again lines not ending with an EOS punct.
    for n in morgunbladid ljosvakamidlar textasafn_arnastofnun; do
        # Start with expanding some abbreviations using regex
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
        -e '/^.*?[^\.\?\!]$/d' \
        < $tmp/rmh_${n}_cleaned.txt \
        > $tmp/rmh_${n}_cleaned_abbrexp.txt
    done
fi

if [ $stage -le 3 ]; then
    echo "Remove duplicates"
    awk '!x[$0]++' $tmp/ljosv_textas_morgunb.cleaned_formatted.txt > $tmp/ljosv_textas_morgunb.cleaned_formatted_uniq.txt
fi

if [ $stage -le 3 ]; then
    
    # Add spaces into acronyms pronounced as letters
    if grep -E -q "[A-ZÁÐÉÍÓÚÝÞÆÖ]{2,}\b" "$intermediate"/text_noPuncts.txt ; then
        grep -E -o "[A-ZÁÐÉÍÓÚÝÞÆÖ]{2,}\b" \
        < "$intermediate"/text_noPuncts.txt  \
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
    
    /bin/sed -f "$tmp"/acro_sed_pattern.tmp "$intermediate"/text_noPuncts.txt \
    > "$intermediate"/text_exp2.txt || error 13 $LINENO "${error_array[13]}";
    
fi

if [ $stage -le 4 ]; then
    
    echo "Fix the casing of words in the text and extract new vocabulary"
    
    #Lowercase what only exists in lc in the prondict and uppercase what only exists in uppercase in the prondict
    
    # Find the vocabulary that appears in both cases in text
    cut -f1 "$prondict" | sort -u \
    | sed -re "s:.+:\l&:" \
    | sort | uniq -d \
    > "$tmp"/prondict_two_cases.tmp || error 14 $LINENO "${error_array[14]}";
    
    # Find words that only appear in upper case in the pron dict
    comm -13 <(sed -r 's:.*:\u&:' "$tmp"/prondict_two_cases.tmp) \
    <(cut -f1 "$prondict" | grep -E "^[A-ZÁÐÉÍÓÚÝÞÆÖ][a-záðéíóúýþæö]" | sort -u) \
    > "$tmp"/propernouns_prondict.tmp || error 14 $LINENO "${error_array[14]}";
    
    comm -13 <(sort -u "$tmp"/prondict_two_cases.tmp) \
    <(cut -f1 "$prondict" | grep -E "^[a-záðéíóúýþæö]" | sort -u) \
    > "$tmp"/only_lc_prondict.tmp || error 14 $LINENO "${error_array[14]}";
    
    # Find words in the new text that are not in the pron dict
    # Exclude words that are abbreviations, acronyms as letters
    # or writing notations which are incorrect or discouraged by Althingi.
    comm -23 <(cut -d' ' -f2- "$intermediate"/text_exp2.txt \
        | tr ' ' '\n' | grep -E -v '[0-9%‰°º²³,.:;?!<> ]' \
        | grep -E -v "\b$(cat $tmp/abbr_pattern.tmp)\b" \
        | grep -vf "$tmp"/abbr_acro_as_letters | grep -vf "$bad_words" \
    | sort -u | grep -E -v '^\s*$' ) \
    <(cut -f1 "$prondict" | sort -u) \
    > "$tmp"/new_vocab_all.txt || error 14 $LINENO "${error_array[14]}";
    sed -i -r 's:^.*Binary file.*$::' "$tmp"/new_vocab_all.txt
    
    if [ -s "$tmp"/new_vocab_all.txt ]; then
        # Find the ones that probably have the incorrect case
        comm -12 "$tmp"/new_vocab_all.txt \
        <(sed -r 's:.+:\l&:' "$tmp"/propernouns_prondict.tmp) \
        > "$intermediate"/to_uppercase.tmp || error 14 $LINENO "${error_array[14]}";
        
        comm -12 "$tmp"/new_vocab_all.txt \
        <(sed -r 's:.+:\u&:' "$tmp"/only_lc_prondict.tmp) \
        > "$intermediate"/to_lowercase.tmp || error 14 $LINENO "${error_array[14]}";
        
        # Lowercase a few words in the text before capitalizing
        tr "\n" "|" < "$intermediate"/to_lowercase.tmp \
        | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" \
        > "$tmp"/to_lowercase_pattern.tmp || error 13 $LINENO "${error_array[13]}";
        
        sed -r 's:(\b'"$(cat "$tmp"/to_lowercase_pattern.tmp)"'\b):\l\1:g' \
        < "$intermediate"/text_exp2.txt \
        > "$intermediate"/text_case1.txt || error 13 $LINENO "${error_array[13]}";
        
        # Capitalize
        tr "\n" "|" < "$intermediate"/to_uppercase.tmp \
        | sed '$s/|$//' | perl -pe "s:\|:\\\b\|\\\b:g" \
        | sed 's:.*:\L&:' > "$tmp"/to_uppercase_pattern.tmp || error 13 $LINENO "${error_array[13]}";
        
        sed -r 's:(\b'"$(cat "$tmp"/to_uppercase_pattern.tmp)"'\b):\u\1:g' \
        < "$intermediate"/text_case1.txt \
        > "$intermediate"/text_case2.txt || error 13 $LINENO "${error_array[13]}";
    else
        cp "$intermediate"/text_exp2.txt "$intermediate"/text_case2.txt
    fi
    
    # Sometimes there are personal names that exist both in upper and lowercase, fix if
    # they have accidentally been lowercased
    tr "\n" "|" < "$tmp"/ambiguous_names \
    | sed '$s/|$//' \
    | perl -pe "s:\|:\\\b\|\\\b:g" \
    | sed 's:.*:\L&:' > "$tmp"/ambiguous_personal_names_pattern.tmp || error 13 $LINENO "${error_array[13]}";
    
    # Fix personal names, company names which are followed by hf, ohf or ehf. Keep single letters lowercased.
    sed -re 's:\b([^ ]+) (([eo])?hf)\b:\u\1 \2:g' \
    -e 's:(\b'"$(cat "$tmp"/ambiguous_personal_names_pattern.tmp)"'\b) ([A-ZÁÉÍÓÚÝÞÆÖ][^ ]+(s[oy]ni?|dótt[iu]r|sen))\b:\u\1 \2:g' \
    -e 's:(\b'"$(cat "$tmp"/ambiguous_personal_names_pattern.tmp)"'\b) ([A-ZÁÉÍÓÚÝÞÆÖ][^ ]*) ([A-ZÁÉÍÓÚÝÞÆÖ][^ ]+(s[oy]ni?|dótt[iu]r|sen))\b:\u\1 \2 \3:g' \
    -e 's:\b([A-ZÁÐÉÍÓÚÝÞÆÖ])\b:\l\1:g' -e 's:[º°]c:°C:g' \
    < "$intermediate"/text_case2.txt > "$textout" || error 13 $LINENO "${error_array[13]}";
fi
exit 0;