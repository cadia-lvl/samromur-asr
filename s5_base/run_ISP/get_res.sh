/home/derik/work/samromur-asr/s5_base/exp_ISP/libri/10h/chain/tdnn10h_sp/decode_dev_clean_6g




# WER info:
echo "$date"
for lang in isl libri; do
    for set in 10h 20h 40h 80h 160h 320h 640h; do 
        for x in exp_ISP/$lang/$set/chain/tdnn${set}_sp/decode_test_clean_8g_rescored ; do
            [ -d "$x" ] && grep WER "$x"/wer_* | utils/best_wer.sh;
        done
    done
done| sed -e "s/%WER //" | sed -e "s/\[ //" | sed -e "s/ \/ / /" | sed -e "s/ sub.*h\/chain\/tdnn/ /" | sed -e "s/_sp\/decode_/ /" | sed -e "s/\// /"  | sed -e "s/wer_//" | sed -e "s/ ins,//" | sed -e "s/ del,//" | sed -e "s/,//" | sed -e "s/ /\t/"




for lang in libri ; do
    for set in 10h 20h 40h 80h 160h 320h 640h; do 
        for x in exp_ISP/$lang/$set/chain/tdnn${set}_sp/decode_{althingi,sm}_test_8g_rescored ; do
            [ -d "$x" ] && grep WER "$x"/wer_* | utils/best_wer.sh;
        done
    done
done | sed -e "s/%WER //" | sed -e "s/\[ //" | sed -e "s/ \/ / /" | sed -e "s/ sub.*h\/chain\/tdnn/ /" | sed -e "s/_sp\/decode_/ /" | sed -e "s/\// /"  | sed -e "s/wer_//" | sed -e "s/ ins,//" | sed -e "s/ del,//" | sed -e "s/,//" | sed -e "s/ /\t/"



| sed -e "s/\/chain.*de_/\t/" | sed -e "s/\/wer.*//" > TDNN_result_isl


