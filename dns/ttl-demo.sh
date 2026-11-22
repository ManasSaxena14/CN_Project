#!/bin/bash
# ───────────────────────────────────────────────────────────
# ttl-demo.sh — Phase 2 Extension B: TTL & OS Caching Demo
#
# Demonstrates:
#   1. Initial lookup showing TTL 30
#   2. The difference between `dig` (bypasses OS cache) and
#      `dscacheutil` / `curl` (uses macOS mDNSResponder cache)
#   3. Cache persistence across record changes until TTL expires
#   4. Immediate cache invalidation via manual flush
#
# Usage:
#   ./dns/ttl-demo.sh
# ───────────────────────────────────────────────────────────
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/config.env"

DOMAIN="app.$PROJECT_DOMAIN"
ORIGINAL_IP="${APP_TARGET_IP:-$MAC2_IP}"
ALT_IP="${STANDBY_EDGE_IP:-$MAC3_IP}"

echo "============================================================"
echo "  PHASE 2 — EXTENSION B: TTL & OS CACHING DEMO"
echo "============================================================"
echo "  Target Domain : $DOMAIN"
echo "  Original IP   : $ORIGINAL_IP (Primary Edge)"
echo "  Alternate IP  : $ALT_IP (Standby Edge / Test IP)"
echo "  Configured TTL: ${DNS_TTL:-30}s"
echo "============================================================"
echo ""

pause() {
    echo ""
    echo -e "\033[1;33m>>> $1\033[0m"
    read -r -p "Press [ENTER] to proceed... " _
    echo ""
}

# ── STEP 1: Query initial state ────────────────────────────
pause "STEP 1: Initial DNS resolution from Client"
echo "1a. Direct query with dig (inspect TTL in Answer section):"
dig "$DOMAIN" | grep -A 2 "ANSWER SECTION" || dig "$DOMAIN"

echo ""
echo "1b. Querying OS Resolver via dscacheutil (how applications resolve names):"
dscacheutil -q host -a name "$DOMAIN" | grep -E "name:|ip_address:" || true

echo ""
echo "------------------------------------------------------------"
echo "VIVA NOTE — dig vs OS cache:"
echo "• dig sends a raw UDP packet directly to port 53 of the nameserver."
echo "  It intentionally BYPASSES the macOS mDNSResponder cache."
echo "• Applications (curl, Safari, python) call getaddrinfo() -> mDNSResponder,"
echo "  which checks its local cache first before making any network query."
echo "------------------------------------------------------------"

# ── STEP 2: Record Change Simulation ──────────────────────
pause "STEP 2: Simulate Record Change on DNS Server(s)"
echo "To test TTL caching, change the record to $ALT_IP on Mac 1 (and Mac 4):"
echo ""
echo "  Run this on Mac 1 (in another terminal tab):"
echo "    sudo ./dns/start-dns.sh --target $ALT_IP"
echo ""
echo "  (If Mac 4 is also running as backup DNS, run the same command on Mac 4)"
echo ""
read -r -p "Press [ENTER] once the DNS server record has been changed to $ALT_IP... " _

# ── STEP 3: Compare dig vs OS cache right after change ─────
pause "STEP 3: Check immediate post-change behavior (dig vs dscacheutil)"

echo "3a. Direct query with dig (bypasses cache -> sees new record immediately):"
NEW_DIG=$(dig +short "$DOMAIN" 2>/dev/null || echo "none")
echo "  dig answer: $NEW_DIG"

echo ""
echo "3b. OS Resolver query via dscacheutil (within ${DNS_TTL:-30}s window):"
OS_IP=$(dscacheutil -q host -a name "$DOMAIN" | grep "ip_address:" | head -1 | awk '{print $2}')
echo "  dscacheutil answer: ${OS_IP:-none}"

echo ""
if [ "$OS_IP" = "$ORIGINAL_IP" ]; then
    echo -e "\033[1;32m✓ PROOF OF CACHING:\033[0m"
    echo "  Even though the authoritative DNS server now returns $NEW_DIG,"
    echo "  macOS is still returning the cached IP ($ORIGINAL_IP)!"
    echo "  This proves client traffic continues to hit the old IP until TTL expires."
else
    echo "Note: dscacheutil returned: $OS_IP (cache may have expired or was empty)."
fi

# ── STEP 4: Demonstrate Manual Cache Invalidation ─────────
pause "STEP 4: Demonstrate Manual Cache Flush"
echo "Flushing local DNS cache on this client..."
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null || true
echo "✓ Cache flushed."

echo ""
echo "Querying OS Resolver again immediately after flush:"
FLUSHED_IP=$(dscacheutil -q host -a name "$DOMAIN" | grep "ip_address:" | head -1 | awk '{print $2}')
echo "  dscacheutil answer now: ${FLUSHED_IP:-none}"
if [ "$FLUSHED_IP" = "$ALT_IP" ]; then
    echo -e "\033[1;32m✓ Cache successfully invalidated!\033[0m OS resolver retrieved the new record."
fi

# ── STEP 5: Restoration ───────────────────────────────────
pause "STEP 5: Restore DNS Server back to original $ORIGINAL_IP"
echo "Restore original DNS target on Mac 1:"
echo "  sudo ./dns/start-dns.sh"
echo ""
read -r -p "Press [ENTER] once restored on Mac 1... " _

sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null || true
echo "Final verification:"
dig +short "$DOMAIN"
echo ""
echo "============================================================"
echo "  TTL Demo Complete!"
echo "============================================================"
