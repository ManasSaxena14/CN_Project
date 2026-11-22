#!/bin/bash
# ───────────────────────────────────────────────────────────
# ping-matrix.sh  — run from Mac 1 to verify L3 connectivity
# Pings every Mac from this Mac. Teammates run it too.
# ───────────────────────────────────────────────────────────
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../config.env"

MACS=("MAC1:$MAC1_IP" "MAC2:$MAC2_IP" "MAC3:$MAC3_IP" "MAC4:$MAC4_IP")
MY_IP=$(ipconfig getifaddr en0 2>/dev/null || echo "unknown")

echo "============================================"
echo " PING MATRIX  (from $(hostname -s) / $MY_IP)"
echo " $(date)"
echo "============================================"
echo ""

RESULTS=""

for entry in "${MACS[@]}"; do
    NAME="${entry%%:*}"
    IP="${entry##*:}"

    if [ "$IP" = "$MY_IP" ]; then
        STATUS="SELF (skip)"
    elif ping -c 3 -W 1 "$IP" &>/dev/null; then
        RTT=$(ping -c 3 -W 1 "$IP" 2>/dev/null | tail -1 | awk -F/ '{print $5}')
        STATUS="✓ OK  (avg ${RTT}ms)"
    else
        STATUS="✗ FAIL"
    fi

    LINE=$(printf "  %-6s  %-16s  %s" "$NAME" "$IP" "$STATUS")
    echo "$LINE"
    RESULTS="$RESULTS$LINE\n"
done

echo ""
echo "============================================"

# Save output
OUT="ping-matrix-$(hostname -s).txt"
echo -e "Ping Matrix from $(hostname -s) / $MY_IP\n$(date)\n\n$RESULTS" > "$OUT"
echo "Saved to $OUT"
