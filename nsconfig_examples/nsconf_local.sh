#!/bin/bash

read -r cmd
cd dns_server
echo "$cmd"|base64 -d>payload.txt
python3 dns_server.py