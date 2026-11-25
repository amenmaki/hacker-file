#!/usr/bin/env bash

# hackerB.sh - Real Local Network Discovery & Device Inspector
# Run only on networks you own or have explicit permission to inspect.

# ANSI Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
NC='\033[0m'

clear

# Big Colorful ASCII Banner: HACKER B
echo -e "${RED}  _   _    _    ____ _  _______ ____      ____  ${NC}"
echo -e "${YELLOW} | | | |  / \  / ___| |/ / ____|  _ \    | __ ) ${NC}"
echo -e "${GREEN} | |_| | / _ \| |   | ' /|  _| | |_) |   |  _ \ ${NC}"
echo -e "${CYAN} |  _  |/ ___ \ |___| . \| |___|  _ <    | |_) |${NC}"
echo -e "${MAGENTA} |_| |_/_/   \_\____|_|\_\_____|_| \_\   |____/ ${NC}"
echo -e "${WHITE}      [ Real Local Network Device Inspector ]${NC}"
echo ""

# Check required core tool
if ! command -v ip >/dev/null 2>&1; then
    echo -e "${RED}[!] Error: 'ip' command not found. Install iproute2 first.${NC}"
    exit 1
fi

# Detect active default IPv4 interface, local IP, gateway, and subnet
IFACE=$(ip -4 route show default | awk '{print $5; exit}')
GATEWAY=$(ip -4 route show default | awk '{print $3; exit}')
LOCAL_IP=$(ip -4 -o addr show dev "$IFACE" | awk '{print $4; exit}' | cut -d'/' -f1)
SUBNET=$(ip -4 route show dev "$IFACE" proto kernel scope link | awk '{print $1; exit}')

if [ -z "$IFACE" ] || [ -z "$SUBNET" ]; then
    echo -e "${RED}[!] Could not detect an active local network interface or subnet.${NC}"
    exit 1
fi

echo -e "${CYAN}=== NETWORK INTERFACE INFO ===${NC}"
echo -e "${YELLOW}Interface  :${NC} ${WHITE}$IFACE${NC}"
echo -e "${YELLOW}Your IP    :${NC} ${WHITE}${LOCAL_IP:-Unknown}${NC}"
echo -e "${YELLOW}Gateway    :${NC} ${WHITE}${GATEWAY:-Unknown}${NC}"
echo -e "${YELLOW}Subnet     :${NC} ${WHITE}$SUBNET${NC}"
echo ""

# Function to resolve real device name using DNS, mDNS (Avahi), or NetBIOS
resolve_hostname() {
    local target_ip="$1"
    local name=""

    # 1. Standard reverse DNS / /etc/hosts lookup
    name=$(getent hosts "$target_ip" 2>/dev/null | awk '{print $2; exit}')

    # 2. mDNS (.local) lookup if avahi-resolve is installed
    if [ -z "$name" ] && command -v avahi-resolve >/dev/null 2>&1; then
        name=$(timeout 1 avahi-resolve -a "$target_ip" 2>/dev/null | awk '{print $2; exit}')
    fi

    # 3. NetBIOS (Windows/Samba) name lookup if nmblookup is installed
    if [ -z "$name" ] && command -v nmblookup >/dev/null 2>&1; then
        name=$(timeout 1 nmblookup -A "$target_ip" 2>/dev/null | awk '/<00>/ && !/<GROUP>/ {print $1; exit}')
    fi

    if [ -z "$name" ]; then
        if [ "$target_ip" = "$GATEWAY" ]; then
            echo "Router / Gateway"
        else
            echo "Unknown-Device"
        fi
    else
        echo "$name"
    fi
}

# Function to lookup MAC hardware vendor from local OUI databases if present
lookup_vendor() {
    local mac="$1"
    local prefix
    prefix=$(echo "$mac" | tr '[:lower:]' '[:upper:]' | cut -d':' -f1-3 | tr -d ':')
    local prefix_colon
    prefix_colon=$(echo "$mac" | tr '[:lower:]' '[:upper:]' | cut -d':' -f1-3)

    if [ -f /usr/share/ieee-data/oui.txt ]; then
        grep -i "^$prefix" /usr/share/ieee-data/oui.txt 2>/dev/null | head -n 1 | cut -f3-
    elif [ -f /usr/share/nmap/nmap-mac-prefixes ]; then
        grep -i "^$prefix " /usr/share/nmap/nmap-mac-prefixes 2>/dev/null | head -n 1 | cut -d' ' -f2-
    elif [ -f /usr/share/wireshark/manuf ]; then
        grep -i "^$prefix_colon" /usr/share/wireshark/manuf 2>/dev/null | head -n 1 | awk '{print $2}'
    else
        echo "OUI database not found locally"
    fi
}

# Populate real ARP/neighbor table across the local /24 subnet
BASE_IP=$(echo "$SUBNET" | cut -d'/' -f1 | awk -F. '{print $1"."$2"."$3}')
echo -e "${BLUE}[*] Scanning local subnet (${BASE_IP}.1 - 254) for live devices...${NC}"

if command -v nmap >/dev/null 2>&1; then
    # Fast real ARP/ping discovery via nmap
    nmap -sn "${BASE_IP}.1-254" -oG - >/dev/null 2>&1
elif command -v ping >/dev/null 2>&1; then
    for i in $(seq 1 254); do
        ping -c 1 -W 1 "${BASE_IP}.${i}" >/dev/null 2>&1 &
    done
    wait
fi

# Read real entries from the kernel neighbor cache
mapfile -t ENTRIES < <(ip neigh show dev "$IFACE" | awk '$1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $5 ~ /:/ && $6 != "FAILED" {print $1 "|" $5 "|" $6}')

if [ "${#ENTRIES[@]}" -eq 0 ]; then
    echo -e "${RED}[!] No active neighbor devices found on $IFACE.${NC}"
    exit 0
fi

echo -e "${GREEN}[+] Found ${#ENTRIES[@]} active device(s) on your network:${NC}"
echo -e "${CYAN}-----------------------------------------------------------------${NC}"
printf "${WHITE}%-4s %-26s %-16s %-18s${NC}\n" "No." "Device Name" "IP Address" "MAC Address"
echo -e "${CYAN}-----------------------------------------------------------------${NC}"

for idx in "${!ENTRIES[@]}"; do
    IFS='|' read -r ip mac state <<< "${ENTRIES[$idx]}"
    hostname=$(resolve_hostname "$ip")
    num=$((idx + 1))
    printf "${YELLOW}%-4s${NC} ${GREEN}%-26s${NC} ${CYAN}%-16s${NC} ${MAGENTA}%-18s${NC}\n" "[$num]" "$hostname" "$ip" "$mac"
done
echo -e "${CYAN}-----------------------------------------------------------------${NC}"
echo ""

# Prompt user to choose a device number
read -r -p "$(echo -e "${WHITE}Enter device number to inspect (1-${#ENTRIES[@]}) or press Enter to exit: ${NC}")" choice

if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#ENTRIES[@]}" ]; then
    echo -e "${YELLOW}[*] Exiting.${NC}"
    exit 0
fi

IFS='|' read -r sel_ip sel_mac sel_state <<< "${ENTRIES[$((choice - 1))]}"
sel_hostname=$(resolve_hostname "$sel_ip")
sel_vendor=$(lookup_vendor "$sel_mac")

echo ""
echo -e "${MAGENTA}=================================================================${NC}"
echo -e "${WHITE}                SELECTED DEVICE FULL VISIBLE INFO                ${NC}"
echo -e "${MAGENTA}=================================================================${NC}"
echo -e "${YELLOW}Device Name      :${NC} ${GREEN}$sel_hostname${NC}"
echo -e "${YELLOW}IPv4 Address     :${NC} ${CYAN}$sel_ip${NC}"
echo -e "${YELLOW}MAC Address      :${NC} ${MAGENTA}$sel_mac${NC}"
echo -e "${YELLOW}Hardware Vendor  :${NC} ${WHITE}${sel_vendor:-Unknown}${NC}"
echo -e "${YELLOW}Neighbor State   :${NC} ${WHITE}$sel_state${NC}"
echo -e "${YELLOW}Network Interface:${NC} ${WHITE}$IFACE${NC}"

# Check live ping latency & TTL (TTL hints at OS family: ~64 Linux/Android/macOS, ~128 Windows)
if command -v ping >/dev/null 2>&1; then
    ping_out=$(ping -c 1 -W 1 "$sel_ip" 2>/dev/null | grep "ttl=")
    if [ -n "$ping_out" ]; then
        ttl_val=$(echo "$ping_out" | sed -n 's/.*ttl=\([0-9]*\).*/\1/p')
        rtt_val=$(echo "$ping_out" | sed -n 's/.*time=\([0-9.]* ms\).*/\1/p')
        echo -e "${YELLOW}Ping Response    :${NC} ${GREEN}Online${NC} (${rtt_val:-N/A}, TTL=${ttl_val:-N/A})"
    else
        echo -e "${YELLOW}Ping Response    :${NC} ${RED}ICMP Blocked / No Reply${NC}"
    fi
fi

# Show raw ARP entry
if command -v arp >/dev/null 2>&1; then
    arp_line=$(arp -n "$sel_ip" 2>/dev/null | tail -n +2)
    [ -n "$arp_line" ] && echo -e "${YELLOW}ARP Cache Entry  :${NC} ${DIM}$arp_line${NC}"
fi

# Show open ports & detected services if nmap is installed
if command -v nmap >/dev/null 2>&1; then
    echo ""
    echo -e "${CYAN}--- Open Ports & Visible Services (Nmap) ---${NC}"
    nmap -F --open "$sel_ip" | grep -E "^[0-9]+/|MAC Address:|Service Info:|OS details:" || echo -e "${DIM}No common open ports detected.${NC}"
fi

echo -e "${MAGENTA}=================================================================${NC}"
