#!/usr/bin/env bash

# hackerB.sh - Show only the connected router/gateway for this Linux device
# Run only on networks you own or have explicit permission to inspect.

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
echo -e "${WHITE}          [ Connected Router Inspector ]${NC}"
echo ""

if ! command -v ip >/dev/null 2>&1; then
    echo -e "${RED}[!] Error: 'ip' command not found. Install iproute2 first.${NC}"
    exit 1
fi

IFACE=$(ip -4 route show default | awk '{print $5; exit}')
GATEWAY=$(ip -4 route show default | awk '{print $3; exit}')
LOCAL_IP=$(ip -4 -o addr show dev "$IFACE" 2>/dev/null | awk '{print $4; exit}' | cut -d'/' -f1)

if [ -z "$IFACE" ] || [ -z "$GATEWAY" ]; then
    echo -e "${RED}[!] No active connected router/gateway found.${NC}"
    exit 1
fi

# Probe only the router IP to refresh its neighbor/ARP entry
if command -v ping >/dev/null 2>&1; then
    ping -c 1 -W 1 "$GATEWAY" >/dev/null 2>&1 || true
fi

ROUTER_MAC=$(ip neigh show dev "$IFACE" 2>/dev/null | awk -v gw="$GATEWAY" '$1 == gw && $5 ~ /:/ && $6 != "FAILED" {print $5; exit}')
ROUTER_STATE=$(ip neigh show dev "$IFACE" 2>/dev/null | awk -v gw="$GATEWAY" '$1 == gw {print $6; exit}')

ROUTER_NAME=$(getent hosts "$GATEWAY" 2>/dev/null | awk '{print $2; exit}')
if [ -z "$ROUTER_NAME" ] && command -v avahi-resolve >/dev/null 2>&1; then
    ROUTER_NAME=$(timeout 1 avahi-resolve -a "$GATEWAY" 2>/dev/null | awk '{print $2; exit}')
fi
[ -z "$ROUTER_NAME" ] && ROUTER_NAME="Connected-Router"

lookup_vendor() {
    local mac="$1"
    [ -z "$mac" ] && echo "Unknown" && return
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

ROUTER_VENDOR=$(lookup_vendor "$ROUTER_MAC")

echo -e "${CYAN}=== CONNECTED ROUTER ONLY ===${NC}"
echo -e "${YELLOW}Router Name      :${NC} ${GREEN}$ROUTER_NAME${NC}"
echo -e "${YELLOW}Router IP        :${NC} ${CYAN}$GATEWAY${NC}"
echo -e "${YELLOW}Router MAC       :${NC} ${MAGENTA}${ROUTER_MAC:-Not in neighbor table}${NC}"
echo -e "${YELLOW}Hardware Vendor  :${NC} ${WHITE}${ROUTER_VENDOR:-Unknown}${NC}"
echo -e "${YELLOW}Neighbor State   :${NC} ${WHITE}${ROUTER_STATE:-Unknown}${NC}"
echo -e "${YELLOW}Linux Interface  :${NC} ${WHITE}$IFACE${NC}"
echo -e "${YELLOW}Your Linux IP    :${NC} ${WHITE}${LOCAL_IP:-Unknown}${NC}"

if command -v ping >/dev/null 2>&1; then
    ping_out=$(ping -c 1 -W 1 "$GATEWAY" 2>/dev/null | grep "ttl=")
    if [ -n "$ping_out" ]; then
        ttl_val=$(echo "$ping_out" | sed -n 's/.*ttl=\([0-9]*\).*/\1/p')
        rtt_val=$(echo "$ping_out" | sed -n 's/.*time=\([0-9.]* ms\).*/\1/p')
        echo -e "${YELLOW}Ping Status      :${NC} ${GREEN}Reachable${NC} (${rtt_val:-N/A}, TTL=${ttl_val:-N/A})"
    else
        echo -e "${YELLOW}Ping Status      :${NC} ${RED}No ICMP reply${NC}"
    fi
fi

if command -v arp >/dev/null 2>&1; then
    arp_line=$(arp -n "$GATEWAY" 2>/dev/null | tail -n +2)
    [ -n "$arp_line" ] && echo -e "${YELLOW}ARP Cache Entry  :${NC} ${DIM}$arp_line${NC}"
fi

echo ""
