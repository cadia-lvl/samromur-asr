uc_minus="\xE2\x9E\x96";
println() { printf "$@\n" >&2; }

println "Running: $0"
println "Cleaning up current working directory"

if [ -L "./utils" ]; then
	rm  ./utils;
	println "\t$uc_minus Symbolic link deleted: ./utils"
fi

if [ -L "./steps" ]; then
	rm  ./steps;
	println "\t$uc_minus Symbolic link deleted: ./steps"
fi

if [ -e "./data" ]; then
	rm -rf ./data;
	println "\t$uc_minus Directory deleted: ./data"
fi

if [ -e "./exp" ]; then
	rm -rf ./exp;
	println "\t$uc_minus Directory deleted: ./exp"
fi

if [ -e "./conf" ]; then
	rm -rf ./conf;
	println "\t$uc_minus Directory deleted: ./conf"
fi

if [ -e "./mfcc" ]; then
	rm -rf ./mfcc;
	println "\t$uc_minus Directory deleted: ./mfcc"
fi