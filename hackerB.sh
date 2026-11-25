#!/usr/bin/env bash

# hackerB.sh - Local network device inspection helper (for networks you own/manage)

if ! command -v ip >/dev/null 2>&1; then
    echo "Error: 'ip' command not found. Install iproute2 first."
    exit 1
fi

IFACE=$(ip -4 route show default | awk '{print $5; exit}')
SUBNET=$(ip -4 route show dev "$IFACE" proto kernel scope link | awk '{print $1; exit}')

if [ -z "$IFACE" ] || [ -z "$SUBNET" ]; then
    echo "Could not detect an active local network interface or subnet."
    exit 1
fi

echo "=== HACKERB LOCAL NETWORK VIEW ==="
echo "Interface : $IFACE"
echo "Subnet    : $SUBNET"
echo ""

if command -v ping >/dev/null 2>&1; then
    BASE_IP=$(echo "$SUBNET" | cut -d'/' -f1 | awk -F. '{print $1"."$2"."$3}')
    echo "Pinging local subnet (${BASE_IP}.1-254) to refresh neighbor table..."
    for i in $(seq 1 254); do
        ping -c 1 -W 1 "${BASE_IP}.${i}" >/dev/null 2>&1 &
    done
    wait
fi

mapfile -t ENTRIES < <(ip neigh show dev "$IFACE" | awk '$1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $4 != "FAILED" {print $1 "|" $5 "|" $4}')

if [ "${#ENTRIES[@]}" -eq 0 ]; then
    echo "No active neighbor devices found on $IFACE."
    exit 0
fi

echo "Discovered Devices:"
echo "---------------------------------------------"
for idx in "${!ENTRIES[@]}"; do
    IFS='|' read -r ip mac state <<< "${ENTRIES[$idx]}"
    hostname=$(getent hosts "$ip" 2>/dev/null | awk '{print $2; exit}')
    [ -z "$hostname" ] && hostname="Unknown Hostname"
    num=$((idx + 1))
    printf "%2d) %-30s (%s)\n" "$num" "$hostname" "$ip"
done
echo "---------------------------------------------"

read -r -p "Choose a device number (or press Enter to exit): " choice

if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#ENTRIES[@]}" ]; then
    echo "Exiting without selecting a device."
    exit 0
fi

IFS='|' read -r sel_ip sel_mac sel_state <<< "${ENTRIES[$((choice - 1))]}"
sel_hostname=$(getent hosts "$sel_ip" 2>/dev/null | awk '{print $2; exit}')
[ -z "$sel_hostname" ] && sel_hostname="Unknown Hostname"

echo ""
echo "=== SELECTED DEVICE DETAILS ==="
echo "Device Name / Hostname : $sel_hostname"
echo "IP Address             : $sel_ip"
echo "MAC Address            : ${sel_mac:-Not available}"
echo "Neighbor State         : ${sel_state:-Unknown}"
echo "Interface              : $IFACE"

if command -v arp >/dev/null 2>&1; then
    arp_line=$(arp -n "$sel_ip" 2>/dev/null | tail -n +2)
    [ -n "$arp_line" ] && echo "ARP Table Entry        : $arp_line"
fi

if command -v nmap >/dev/null 2>&1; then
    echo ""
    echo "--- Quick Nmap Host Info ---"
    nmap -sn "$sel_ip"
fi

