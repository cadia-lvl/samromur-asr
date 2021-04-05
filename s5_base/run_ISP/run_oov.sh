

for decode_set in sm_dev_hires sm_test_hires althingi_dev_hires althingi_test_hires; do
    ./run_ISP/oov.py data_ISP/sm/$decode_set/text data_ISP/isl_lang/words.txt data_ISP/sm/$decode_set/oov
done

In the file:data_ISP/sm/sm_dev_hires/text
there are 249 or a 0.00026035866759099223% oovs rate

In the file:data_ISP/sm/sm_test_hires/text
there are 284 or a 0.0002969552674531799% oovs rate

In the file:data_ISP/sm/althingi_dev_hires/text
there are 290 or a 0.0003032289702866978% oovs rate

In the file:data_ISP/sm/althingi_test_hires/text
there are 306 or a 0.0003199588445094121% oovs rate