
. ./utils.sh

println "Running: $BASH_SOURCE";

export conf_dir="./conf";
export exp_dir="./exp";
export data_dir="./data";
export data_train_dir="$data_dir/train";
export data_test_dir="$data_dir/test";
export data_local_dir="$data_dir/local";
export data_local_lang_dir="$data_dir/local/lang";
export data_local_dict_dir="$data_dir/local/dict";

export mfcc_conf_file="$conf_dir/mfcc.conf"

export train_text_file="$data_train_dir/text";
export train_words_file="$data_train_dir/words.txt"
export train_wav_scp_file="$data_train_dir/wav.scp";
export train_utt2spk_file="$data_train_dir/utt2spk";
export train_spk2utt_file="$data_train_dir/spk2utt";
export train_spk2gender_file="$data_train_dir/spk2gender";

export test_text_file="$data_test_dir/text";
export test_words_file="$data_test_dir/words.txt"
export test_wav_scp_file="$data_test_dir/wav.scp";
export test_utt2spk_file="$data_test_dir/utt2spk";
export test_spk2utt_file="$data_test_dir/spk2utt";
export test_spk2gender_file="$data_test_dir/spk2gender";

export lexicon_file="$data_local_lang_dir/lexicon.txt";
export nonsilence_phones_file="$data_local_lang_dir/nonsilence_phones.txt";
export optional_silence_file="$data_local_lang_dir/optional_silence.txt";
export silence_phones_file="$data_local_lang_dir/silence_phones.txt";
export extra_questions="$data_local_lang_dir/extra_questions.txt";

if [ -z "$@" ]
then
	# Preparing filesystem
	println ""
	println "Preparing Filesystem:";

	for dir in \
		$conf_dir \
		$exp_dir \
		$data_dir \
		$data_train_dir \
		$data_test_dir \
		$data_local_dir \
		$data_local_lang_dir \
		$data_local_dict_dir; do
		
		## Check if directory already exists
		if [[ ! -e $dir ]]; then
			### If not, create new directory
			mkdir $dir;
			println "\t$uc_add Directory created: $dir";
		else
			### Else, do nothing
			println "\t$uc_check_mark $dir";
		fi
	done

	for file in \
		$mfcc_conf_file \
		$train_text_file \
		$train_words_file \
		$train_wav_scp_file \
		$train_utt2spk_file \
		$train_spk2utt_file \
		$train_spk2gender_file \
		$test_text_file \
		$test_words_file \
		$test_wav_scp_file \
		$test_utt2spk_file \
		$test_spk2utt_file \
		$test_spk2gender_file \
		$nonsilence_phones_file \
		$optional_silence_file \
		$silence_phones_file \
		$extra_questions; do
		
		# Check if file already exists
		if [[ ! -e $file ]]; then
			### If not, create new file
			touch $file;
			println "\t$uc_add File created: $file";
		else
			### Else, clear the content of the file
			> $file;
			println "\t$uc_check_mark $file";
		fi
	done

	# Create symbolic links to wjs/utils and wjs/steps
	if ! [ -L "./utils" ]; then
		# If symbolic link doesn't exists
		ln -s $KALDI_ROOT/egs/wsj/s5/utils utils || ( println "$uc_attention_mark Error: Cannot create a symbolic link to $KALDI_ROOT/egs/wsj/s5/utils" && exit 1 ) ;
		println "\t$uc_add Symbolic link created: ./utils -> $KALDI_ROOT/egs/wsj/s5/utils";
	else
		println "\t$uc_check_mark ./utils -> $KALDI_ROOT/egs/wsj/s5/utils"
	fi

	if ! [ -L "./steps" ]; then
		# If symbolic link doesn't exists
		ln -s $KALDI_ROOT/egs/wsj/s5/steps steps || ( println "$uc_attention_mark Error: Cannot create a symbolic link to $KALDI_ROOT/egs/wsj/s5/steps" && exit 1 ) ;
		println "\t$uc_add Symbolic link created: ./steps -> $KALDI_ROOT/egs/wsj/s5/steps";
	else
		println "\t$uc_check_mark ./steps -> $KALDI_ROOT/egs/wsj/s5/steps"
	fi

fi
