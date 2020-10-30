#!/bin/bash

read -r cmd
scp -i key dnsns.py user@NAMESERVER:
echo "$cmd"|ssh -i key user@NAMESERVER 'cat>payload.txt;python3 dnsns.py dnshost dnshost.nameserver'
