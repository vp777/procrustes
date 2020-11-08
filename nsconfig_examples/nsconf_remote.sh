#!/bin/bash

read -r cmd
cd dns_server
scp -i key dns_server.py user@NAMESERVER:
echo "$cmd"|ssh -i key user@NAMESERVER 'cat>payload.txt;python3 dns_server.py'
