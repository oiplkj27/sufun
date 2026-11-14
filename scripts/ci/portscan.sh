#!/usr/bin/env bash
# Port scan of the test VM from the CI host (security audit, docs/security-audit.md).
#   bash scripts/ci/portscan.sh <vm-name>        started by run_vm (qemu-common.sh)
#   bash scripts/ci/portscan.sh --setup          make the scan network (qemu-test.sh)
#   bash scripts/ci/portscan.sh --teardown
#
# The scan network is a private cable between this machine and the VM (a "tap"
# device, 10.77.0.1 <-> 10.77.0.2); only our own test VM is on it. Nothing else
# is ever scanned.
#   1. the VM prints "SUFUN-TEST: PORTSCAN-READY" and waits
#   2. nmap: every TCP port (1-65535) and the usual UDP ports of desktop services
#   3. the result is served on http://10.77.0.1:8099/result; the VM reads it and
#      reports PASS/FAIL like its other checks
# Needs: sudo, nmap, dnsmasq (gives the VM its address), python3.
TAP=sufuntap HOST=10.77.0.1 VM=10.77.0.2
UDP_PORTS=53,67,68,69,123,137,138,161,500,631,1716,1900,3702,5353,5355,27031-27036

case ${1:-} in
  --setup)
    sudo ip tuntap add dev "$TAP" mode tap user "$(id -un)" || exit 1
    sudo ip addr add "$HOST/24" dev "$TAP" && sudo ip link set "$TAP" up || exit 1
    # DHCP for the VM: one address, no gateway and no DNS (the VM keeps using its
    # normal network card for the internet)
    sudo dnsmasq --interface="$TAP" --bind-interfaces --except-interface=lo --port=0 --leasefile-ro \
      --dhcp-range="$VM,$VM,255.255.255.0,1h" --dhcp-option=3 --dhcp-option=6 \
      || echo "dnsmasq did not start: the VM will set its address itself"
    exit 0 ;;
  --teardown)
    sudo pkill -f "dnsmasq --interface=$TAP" 2>/dev/null
    pkill -f "http.server 8099" 2>/dev/null
    sudo ip link del "$TAP" 2>/dev/null
    exit 0 ;;
esac

name=${1:?vm name}
pkill -f "http.server 8099" 2>/dev/null
rm -rf "$name-scan"; mkdir -p "$name-scan"
sudo nmap -n -sS -p- --min-rate 1500 --max-retries 2 -oG "$name-nmap-tcp.txt" "$VM" > "$name-nmap-tcp.log" 2>&1
sudo nmap -n -sU -p "$UDP_PORTS" --max-retries 2 -oG "$name-nmap-udp.txt" "$VM" > "$name-nmap-udp.log" 2>&1
sudo chmod a+r "$name"-nmap-*.txt 2>/dev/null
reached=0; grep -q 'Status: Up' "$name-nmap-tcp.txt" 2>/dev/null && reached=1
tcp=$(grep -oE '[0-9]+/open/tcp' "$name-nmap-tcp.txt" 2>/dev/null | cut -d/ -f1 | tr '\n' ' ')
udp=$(grep -oE '[0-9]+/open/udp' "$name-nmap-udp.txt" 2>/dev/null | cut -d/ -f1 | tr '\n' ' ')
echo "REACHED=$reached OPEN_TCP=$(wc -w <<< "$tcp") OPEN_UDP=$(wc -w <<< "$udp") (tcp 1-65535 open: [${tcp% }]; udp $UDP_PORTS answering: [${udp% }])" \
  | tee "$name-portscan.txt" > "$name-scan/result"
echo "== $name port scan: $(cat "$name-portscan.txt")"
cd "$name-scan" && exec timeout 900 python3 -m http.server 8099 --bind "$HOST" >/dev/null 2>&1
