#!/bin/bash

read -r cmd
echo "$cmd"|base64 -d>payload.txt
python3 dnsns.py dnshost dnshost.nameserver