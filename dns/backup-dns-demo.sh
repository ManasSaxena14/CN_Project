#!/bin/bash
# ───────────────────────────────────────────────────────────
# backup-dns-demo.sh — Phase 2 Extension A: Backup DNS Failover
#
# Demonstrates:
#   1. Client configured with Primary ($MAC1_IP) & Backup ($BACKUP_DNS_IP)
#   2. Inspecting resolver configuration with `scutil --dns`
#   3. Active resolution from Primary DNS
#   4. Primary failure simulation (stop dnsmasq on Mac 1)
#   5. Seamless failover to Backup DNS on Mac 4
#   6. Viva concept: DNS service failure vs Application failure
# ───────────────────────────────────────────────────────────
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/config.env"

DOMAIN="app.$PROJECT_DOMAIN"

echo "============================================================"
echo "  PHASE 2 — EXTENSION A: BACKUP DNS FAILOVER DEMO"
echo "============================================================"
echo "  Primary DNS : $MAC1_IP (Mac 1)"
echo "  Backup DNS  : $BACKUP_DNS_IP (Mac 4)"
echo "  Domain      : $DOMAIN"
echo "============================================================"
echo ""

pause() {
    echo ""
    echo -e "\033[1;33m>>> $1\033[0m"
    read -r -p "Press [ENTER] to proceed... " _
    echo ""
}

# ── STEP 1: Ensure Client is Configured for Both DNS Servers ─
pause "STEP 1: Verify Dual DNS Configuration on Client"
echo "Current DNS servers configured for Wi-Fi:"
networksetup -getdnsservers Wi-Fi 2>/dev/null || true

echo ""
echo "Inspecting macOS resolver table via scutil --dns:"
scutil --dns | grep -A 6 "resolver #1" || true

echo ""
echo "------------------------------------------------------------"
echo "VIVA NOTE — macOS Resolver Architecture:"
echo "• scutil --dns shows the resolver table constructed by configd."
echo "• Unlike Linux (/etc/resolv.conf query timeout 5s per server),"
echo "  macOS mDNSResponder manages background health of nameservers."
echo "  If the primary fails, queries dynamically divert to the secondary."
echo "------------------------------------------------------------"

# ── STEP 2: Normal Resolution via Primary DNS ──────────────
pause "STEP 2: Test Normal DNS Query (Primary Active)"
echo "Running dig to check resolving server:"
dig "$DOMAIN" | grep -E "SERVER:|ANSWER SECTION" -A 2 || dig "$DOMAIN"

# ── STEP 3: Simulate Primary DNS Failure ───────────────────
pause "STEP 3: Simulate Primary DNS Server Failure on Mac 1"
echo "Stop dnsmasq on Mac 1:"
echo "  - In Mac 1's terminal running start-dns.sh: press Ctrl+C"
echo "  - Or run: sudo killall dnsmasq"
echo ""
echo "Make sure Mac 4 IS currently running backup DNS:"
echo "  sudo ./dns/start-dns.sh (on Mac 4)"
echo ""
read -r -p "Press [ENTER] once Mac 1 DNS is stopped and Mac 4 DNS is running... " _

# ── STEP 4: Verify Failover to Backup DNS ───────────────────
pause "STEP 4: Query from Client — Observe Failover to Mac 4"
echo "Flushing client DNS cache so next query goes over the network:"
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null || true

echo ""
echo "Sending DNS query from client (note the SERVER line):"
DIG_OUTPUT=$(dig "$DOMAIN")
echo "$DIG_OUTPUT" | grep -A 2 "ANSWER SECTION" || true
echo "$DIG_OUTPUT" | grep ";; SERVER:"

SERVER_USED=$(echo "$DIG_OUTPUT" | grep ";; SERVER:" | awk '{print $3}')
echo ""
echo "Server that answered: $SERVER_USED"
if echo "$SERVER_USED" | grep -q "$BACKUP_DNS_IP"; then
    echo -e "\033[1;32m✓ FAILOVER SUCCESS:\033[0m Query was answered by Backup DNS ($BACKUP_DNS_IP)!"
else
    echo "Queried server: $SERVER_USED (check if Mac 1 is fully stopped and Mac 4 is reachable)."
fi

# ── STEP 5: Explanation for Viva ───────────────────────────
echo ""
echo "============================================================"
echo "VIVA DISTINCTION — DNS Service Failure vs App Server Failure:"
echo "============================================================"
echo "1. DNS Service Failure (Ext A):"
echo "   • When Mac 1 stops, the client cannot translate the name team1.test."
echo "   • Layer 7 resolution failure (UDP 53 timeout / no response)."
echo "   • Result without backup DNS: 'Could not resolve host' / NXDOMAIN."
echo "   • Solved by: Backup DNS server on Mac 4."
echo ""
echo "2. Application Server Failure (e.g. Backend down / nginx down):"
echo "   • DNS resolution succeeds and returns the edge IP perfectly."
echo "   • The failure occurs at Layer 4 (TCP SYN fails -> Connection Refused)"
echo "     or Layer 7 HTTP (nginx returns '502 Bad Gateway')."
echo "   • Solved by: Load balancer retry (proxy_next_upstream) or Standby Edge (Ext E)."
echo "============================================================"
