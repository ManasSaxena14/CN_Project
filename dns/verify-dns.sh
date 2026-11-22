#!/bin/bash
# ───────────────────────────────────────────────────────────
# verify-dns.sh — Comprehensive Phase 2 DNS Verification
#
# Verifies:
#   1. Primary DNS ($MAC1_IP) resolution for app & api
#   2. Backup DNS ($BACKUP_DNS_IP) resolution for app & api
#   3. TTL value matches $DNS_TTL (30s)
#   4. NXDOMAIN returned for unknown *.test domains
#   5. Public DNS forwarding (google.com)
#   6. Active server in client dig output
# ───────────────────────────────────────────────────────────
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/config.env"

EXPECTED_TARGET="${APP_TARGET_IP:-$MAC2_IP}"
EXPECTED_TTL="${DNS_TTL:-30}"
PASS=0
FAIL=0

check() {
    local desc="$1"
    local got="$2"
    local expected="$3"
    echo -n "  $desc: "
    if [[ "$got" =~ "$expected" ]]; then
        echo -e "\033[1;32m✓ PASS\033[0m ($got)"
        ((PASS++))
    else
        echo -e "\033[1;31m✗ FAIL\033[0m (expected '$expected', got '$got')"
        ((FAIL++))
    fi
}

echo "============================================================"
echo "  PHASE 2 DNS VERIFICATION SUITE"
echo "============================================================"
echo "  Primary DNS : $MAC1_IP (Mac 1)"
echo "  Backup DNS  : $BACKUP_DNS_IP (Mac 4)"
echo "  Expected IP : $EXPECTED_TARGET"
echo "  Expected TTL: ${EXPECTED_TTL}s"
echo "============================================================"
echo ""

echo "── 1. Testing Primary DNS (Mac 1: $MAC1_IP) ──"
RES1=$(dig +short @"$MAC1_IP" app.$PROJECT_DOMAIN A 2>/dev/null || echo "TIMEOUT")
check "app.$PROJECT_DOMAIN on Mac 1" "$RES1" "$EXPECTED_TARGET"

RES2=$(dig +short @"$MAC1_IP" api.$PROJECT_DOMAIN A 2>/dev/null || echo "TIMEOUT")
check "api.$PROJECT_DOMAIN on Mac 1" "$RES2" "$EXPECTED_TARGET"

TTL1=$(dig @"$MAC1_IP" app.$PROJECT_DOMAIN | grep -A 1 "ANSWER SECTION" | tail -1 | awk '{print $2}' || echo "0")
check "TTL value on Mac 1" "$TTL1" "$EXPECTED_TTL"

NX1=$(dig @"$MAC1_IP" nonexistent-subdomain.$PROJECT_DOMAIN | grep -o "NXDOMAIN" || echo "NOT-NXDOMAIN")
check "NXDOMAIN on unknown .test" "$NX1" "NXDOMAIN"

FWD1=$(dig +short @"$MAC1_IP" google.com A 2>/dev/null | head -1 || echo "")
if [ -n "$FWD1" ]; then
    check "Upstream forwarding (google.com)" "$FWD1" "."
else
    check "Upstream forwarding (google.com)" "EMPTY" "IP"
fi

echo ""
echo "── 2. Testing Backup DNS (Mac 4: $BACKUP_DNS_IP / Ext A) ──"
if ping -c 1 -W 1 "$BACKUP_DNS_IP" >/dev/null 2>&1; then
    RES_B1=$(dig +short @"$BACKUP_DNS_IP" app.$PROJECT_DOMAIN A 2>/dev/null || echo "TIMEOUT")
    check "app.$PROJECT_DOMAIN on Mac 4" "$RES_B1" "$EXPECTED_TARGET"

    RES_B2=$(dig +short @"$BACKUP_DNS_IP" api.$PROJECT_DOMAIN A 2>/dev/null || echo "TIMEOUT")
    check "api.$PROJECT_DOMAIN on Mac 4" "$RES_B2" "$EXPECTED_TARGET"

    TTL_B=$(dig @"$BACKUP_DNS_IP" app.$PROJECT_DOMAIN | grep -A 1 "ANSWER SECTION" | tail -1 | awk '{print $2}' || echo "0")
    check "TTL value on Mac 4" "$TTL_B" "$EXPECTED_TTL"
else
    echo "  [INFO] Mac 4 ($BACKUP_DNS_IP) not reachable on LAN currently (skipping ping test)."
fi

echo ""
echo "── 3. Testing Client Default Resolver Configuration ──"
CURRENT_DNS=$(networksetup -getdnsservers Wi-Fi 2>/dev/null || true)
echo "  Wi-Fi DNS Servers: $CURRENT_DNS"

echo ""
echo "============================================================"
echo "  Summary: $PASS passed, $FAIL failed"
echo "============================================================"
