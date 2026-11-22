#!/bin/bash
# ───────────────────────────────────────────────────────────
# set-client-dns.sh  — Point a Mac's Wi-Fi DNS at Mac 1
#
# Usage:
#   sudo ./dns/set-client-dns.sh set       # point to Mac 1
#   sudo ./dns/set-client-dns.sh restore   # restore to DHCP default
# ───────────────────────────────────────────────────────────
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/config.env"

ACTION="${1:-set}"

echo ""
if [ "$ACTION" = "restore" ]; then
    echo "Restoring Wi-Fi DNS to DHCP defaults..."
    sudo networksetup -setdnsservers Wi-Fi Empty
    echo "  → DNS reset to automatic (DHCP)"
else
    echo "Setting Wi-Fi DNS to Mac 1 ($MAC1_IP)..."
    sudo networksetup -setdnsservers Wi-Fi "$MAC1_IP"
    echo "  → DNS set to $MAC1_IP"
fi

echo ""
echo "Flushing DNS cache..."
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null || true
echo "  → Cache flushed"

echo ""
echo "Current DNS servers:"
networksetup -getdnsservers Wi-Fi
echo ""

echo "Verifying with dig..."
dig +short app.team1.test A 2>/dev/null || echo "(no answer)"
echo ""
