

filenames=$(cut -f 3 metadata.tsv)

for x in $filenames; do 
    speaker_id=$(echo $x | sed -e 's/\-.*//g') 
    status=$(grep $x metadata.tsv | cut -f19)
    mkdir -p audio/$status/$speaker_id/
    cp a/$x audio/$status/$speaker_id
done