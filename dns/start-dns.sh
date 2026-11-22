#!/bin/bash
# ───────────────────────────────────────────────────────────
# start-dns.sh  — Start the DNS server on Mac 1
#
# Option 1 (recommended): dnsmasq  — production-grade, supports
#   forwarding + NXDOMAIN for .test + TTL 60 out of the box.
# Option 2: Python dns_server.py from setup.sh
#
# Usage:
#   sudo ./dns/start-dns.sh           # dnsmasq (default)
#   sudo ./dns/start-dns.sh python    # python server
# ───────────────────────────────────────────────────────────
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/config.env"

MODE="${1:-dnsmasq}"

# Kill anything already on port 53
sudo lsof -ti :53 2>/dev/null | xargs -r kill 2>/dev/null || true
sleep 1

if [ "$MODE" = "python" ]; then
    echo ""
    echo "Starting Python DNS server..."
    echo "  app.team1.test → $MAC2_IP"
    echo "  api.team1.test → $MAC2_IP"
    echo ""
    # First run setup.sh mac1 to generate the script
    if [ ! -f "$HOME/cn-phase1/dns/dns_server.py" ]; then
        echo "Running setup.sh mac1 first..."
        cd "$PROJECT_DIR" && ./setup.sh mac1
    fi
    sudo python3 "$HOME/cn-phase1/dns/dns_server.py"
else
    echo ""
    echo "Starting dnsmasq DNS server..."
    echo "  Config: $SCRIPT_DIR/dnsmasq.conf"
    echo "  app.team1.test → $MAC2_IP"
    echo "  api.team1.test → $MAC2_IP"
    echo "  Other .test    → NXDOMAIN"
    echo "  Everything else → 8.8.8.8 (internet)"
    echo ""

    # Update the MAC2_IP in dnsmasq.conf from config.env
    sed -i '' "s|address=/app.team1.test/.*|address=/app.team1.test/$MAC2_IP|" "$SCRIPT_DIR/dnsmasq.conf"
    sed -i '' "s|address=/api.team1.test/.*|address=/api.team1.test/$MAC2_IP|" "$SCRIPT_DIR/dnsmasq.conf"

    sudo dnsmasq --conf-file="$SCRIPT_DIR/dnsmasq.conf"
fi
