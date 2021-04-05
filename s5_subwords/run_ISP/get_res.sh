



# WER info:
echo "$date"
for lang in libri; do
    for set in 10h 20h 40h 80h 160h 320h 640h; do 
        for x in exp_ISP/$lang/$set/chain/tdnn${set}_sp/decode_{test,dev}_clean_{6,8}g{_rescored,} ; do
            [ -d "$x" ] && grep WER "$x"/wer_* | utils/best_wer.sh;
        done
    done
done > TDNN_results_libri

%WER 
\[.*exp_ISP/libri/\d+h/chain/tdnn\d+h_sp/decode_
[_g\d]*/wer.*


for lang in isl ; do
    for set in 10h 20h 40h 80h 160h 320h 640h; do 
        for x in exp_ISP/$lang/$set/chain/tdnn${set}_sp/decode_{althingi,sm}_{test,dev}_{6,8}g{_rescored,} ; do
            [ -d "$x" ] && grep WER "$x"/wer_* | utils/best_wer.sh;
        done
    done
done > TDNN_result_isl
