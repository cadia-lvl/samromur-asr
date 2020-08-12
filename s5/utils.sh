# Unicode characters
uc_check_mark="\xe2\x9c\x94";
uc_cross_mark="\xe2\x9c\x96";
uc_attention_mark="\xE2\x9D\x97";
uc_add="\xE2\x9E\x95";
uc_minus="\xE2\x9E\x96";
uc_stars="\xe2\x9c\xa8";

# Our custom print funciton 
println() { printf "$@\n" >&2; }
path() { eval ${$@/text//\/\//\/}; }

# Spinner from http://fitnr.com/showing-a-bash-spinner.html
spinner()
{
    local pid=$1
    local delay=0.75
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}