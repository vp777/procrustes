#! /usr/bin/env python3

#original source: https://github.com/no0be/DNSlivery

import sys
import os
import argparse
import signal
import re
import base64
from scapy.all import *

end_of_transmission_ipv4="4.4.4.4"

banner = """
DNSlivery - Easy files and payloads delivery over DNS
"""

def log(message, msg_type = ''):
    reset   = '\033[0;m'

    # set default prefix and color
    prefix  = '[*]'
    color   = reset

    # change prefix and color based on msg_type
    if msg_type == '+':
        prefix  = '[+]'
        color   = '\033[1;32m'
    elif msg_type == '-':
        prefix  = '[-]'
        color   = '\033[1;31m'
    elif msg_type == 'debug':
        prefix  = '[DEBUG]'
        color   = '\033[0;33m'

    print('%s%s %s%s' % (color, prefix, message, reset))

def base64_chunks(clear, size):
    encoded = base64.b64encode(clear)

    # split base64 into chunks of provided size
    encoded_chunks = []
    for i in range(0, len(encoded), size):
        encoded_chunks.append(encoded[i:i + size])

    return encoded_chunks
    
def ipv4_chunks(clear):
    return list(map(lambda x: '.'.join(map(lambda y: str(y), x)), zip(*[iter(clear+b" "*3)]*4)))+[end_of_transmission_ipv4]
    

def signal_handler(signal, frame):
    log('Exiting...')
    sys.exit(0)

def dns_handler(data):
    # only process dns queries
    if data.haslayer(UDP) and data.haslayer(DNS) and data.haslayer(DNSQR):
        # split packet layers
        ip = data.getlayer(IP)
        udp = data.getlayer(UDP)
        dns = data.getlayer(DNS)
        dnsqr = data.getlayer(DNSQR)

        # only process a queries (type 1)
        if len(dnsqr.qname) != 0 and dnsqr.qtype == 1:
            if args.verbose: log('Received DNS query for %s from %s' % (dnsqr.qname.decode(), ip.src))

            # remove domain part of fqdn and split the different parts of hostname
            hostname = re.sub('\.%s\.?$' % args.domain, '', dnsqr.qname.decode()).split('.')
            if not hostname: return
            
            index_match = re.findall(r'\d+$', hostname[0])
            if not index_match: return
            index = int(index_match[0])
            
            
            if index <= len(chunks):
                response = chunks[index-1]
                log('Delivering payload chunk %s/%d (%s)' % (index, len(chunks), response), '+')

            else: return

            # build response packet
            rdata = response
            rcode = 0
            dn = args.domain
            an = (None, DNSRR(rrname=dnsqr.qname, type='A', rdata=rdata, ttl=1))[rcode == 0]
            ns = DNSRR(rrname=dnsqr.qname, type='NS', ttl=1, rdata=args.nameserver)

            response_pkt = IP(id=ip.id, src=ip.dst, dst=ip.src) / UDP(sport=udp.dport, dport=udp.sport) / DNS(id=dns.id, qr=1, rd=1, ra=1, rcode=rcode, qd=dnsqr, an=an, ns=ns)
            send(response_pkt, verbose=0, iface=args.interface)
        

if __name__ == '__main__':
    # parse args
    parser = argparse.ArgumentParser(description = banner)
    parser.add_argument('domain', default=None, help='FQDN name of the DNS zone')
    parser.add_argument('nameserver', default=None, help='FQDN name of the server running DNSlivery')
    parser.add_argument('-f', '--file', default='payload.txt', help='the file with the payload')
    parser.add_argument('-i', '--interface', default='-', help='interface to listen to DNS traffic, defaults to conf.iface')
    parser.add_argument('-p', '--path', default='.', help='path of directory to serve over DNS (default: pwd)')
    parser.add_argument('-s', '--size', default='255', help='size in bytes of base64 chunks (default: 255)')
    parser.add_argument('-v', '--verbose', action='store_true', help='increase verbosity')
    args = parser.parse_args()

    print('%s' % banner)

    
    if args.interface == "-":
        args.interface = conf.iface
        log('No interface specified, using %s' % (conf.iface))
    
    # verify root
    if os.geteuid() != 0:
        log('Script needs to be run with root privileges to listen for incoming udp/53 packets', '-')
        sys.exit(-1)

    # verify path exists and is readable
    abspath = os.path.abspath(args.path)
    
    if not os.path.exists(abspath) or not os.path.isdir(abspath):
        log('Path %s does not exist or is not a directory' % abspath, '-')
        sys.exit(-1)

    # list files in path
    filenames = {args.file:''}

    chunks = []

    if not args.size.isdecimal():
        log('Incorrect size value for base64 chunks', '-')
        sys.exit(-1)

    size = int(args.size)

    name = args.file
    try:
        # compute base64 chunks of files
        with open(os.path.join(abspath, name), 'rb') as f: chunks = ipv4_chunks(f.read())

    except:
        # remove key from dict in case of failure (e.g. file permissions)
        del filenames[name]
        log('Error computing base64 for %s, file will been ignored' % name, '-')
        
    # display file ready for delivery
    log('File "%s" ready for delivery at x.%s (%d chunks)' % (name, args.domain, len(chunks)))

    # register signal handler
    signal.signal(signal.SIGINT, signal_handler)

    # listen for DNS query
    log('Listening for DNS queries...')

    while True: dns_listener = sniff(filter='udp dst port 53', iface=args.interface, prn=dns_handler)