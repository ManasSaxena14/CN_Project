#!/bin/bash
# ───────────────────────────────────────────────────────────
# verify-dns.sh  — Verify the DNS server is working correctly
# Run from Mac 1 (or any Mac pointing to Mac 1 as DNS)
# ───────────────────────────────────────────────────────────
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/config.env"

DNS="$MAC1_IP"
PASS=0
FAIL=0

echo ""
echo "============================================"
echo " DNS VERIFICATION  (server: $DNS)"
echo "============================================"
echo ""

# ── Test 1: app.team1.test → MAC2_IP ──
echo "1. dig @$DNS app.team1.test A"
RESULT=$(dig +short @"$DNS" app.team1.test A 2>/dev/null)
echo "   Result: $RESULT"
if [ "$RESULT" = "$MAC2_IP" ]; then
    echo "   ✓ PASS (expected $MAC2_IP)"
    ((PASS++))
else
    echo "   ✗ FAIL (expected $MAC2_IP, got '$RESULT')"
    ((FAIL++))
fi
echo ""

# ── Test 2: api.team1.test → MAC2_IP ──
echo "2. dig @$DNS api.team1.test A"
RESULT=$(dig +short @"$DNS" api.team1.test A 2>/dev/null)
echo "   Result: $RESULT"
if [ "$RESULT" = "$MAC2_IP" ]; then
    echo "   ✓ PASS"
    ((PASS++))
else
    echo "   ✗ FAIL (expected $MAC2_IP, got '$RESULT')"
    ((FAIL++))
fi
echo ""

# ── Test 3: unknown .test name → NXDOMAIN ──
echo "3. dig @$DNS doesnotexist.test (expect NXDOMAIN)"
STATUS=$(dig @"$DNS" doesnotexist.test A 2>/dev/null | grep -o "NXDOMAIN" || echo "NOT-NXDOMAIN")
echo "   Result: $STATUS"
if [ "$STATUS" = "NXDOMAIN" ]; then
    echo "   ✓ PASS"
    ((PASS++))
else
    echo "   ✗ FAIL (expected NXDOMAIN)"
    ((FAIL++))
fi
echo ""

# ── Test 4: google.com forwards correctly ──
echo "4. dig @$DNS google.com (expect forwarded answer)"
RESULT=$(dig +short @"$DNS" google.com A 2>/dev/null | head -1)
echo "   Result: $RESULT"
if [ -n "$RESULT" ]; then
    echo "   ✓ PASS (forwarded to upstream)"
    ((PASS++))
else
    echo "   ✗ FAIL (no answer — forwarding broken?)"
    ((FAIL++))
fi
echo ""

# ── Test 5: check SERVER line shows our DNS ──
echo "5. Checking SERVER line in dig output"
SERVER_LINE=$(dig @"$DNS" app.team1.test 2>/dev/null | grep "^;; SERVER:" || echo "none")
echo "   $SERVER_LINE"
if echo "$SERVER_LINE" | grep -q "$DNS"; then
    echo "   ✓ PASS (SERVER is $DNS#53)"
    ((PASS++))
else
    echo "   ✗ FAIL (SERVER should be $DNS#53)"
    ((FAIL++))
fi

echo ""
echo "============================================"
echo " Results: $PASS passed, $FAIL failed"
echo "============================================"
