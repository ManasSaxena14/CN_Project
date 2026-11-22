#!/bin/bash
# ───────────────────────────────────────────────────────────
# collect-network-info.sh   — run on EVERY Mac to gather info
# Output is saved to network-info-<hostname>.txt
# ───────────────────────────────────────────────────────────
set -e

OUT="network-info-$(hostname -s).txt"

{
echo "============================================"
echo " Network Info for $(hostname -s)"
echo " Date: $(date)"
echo "============================================"
echo ""

echo "--- IPv4 Address ---"
ipconfig getifaddr en0 2>/dev/null || echo "(no en0 address)"

echo ""
echo "--- Subnet Mask ---"
ipconfig getoption en0 subnet_mask 2>/dev/null || echo "(unavailable)"

echo ""
echo "--- Default Gateway ---"
route -n get default 2>/dev/null | grep gateway || echo "(unavailable)"

echo ""
echo "--- Interface Name & MAC Address ---"
ifconfig en0 2>/dev/null | head -6

echo ""
echo "--- Wi-Fi SSID ---"
networksetup -getairportnetwork en0 2>/dev/null || echo "(unavailable)"

echo ""
echo "--- Full Hardware Ports ---"
networksetup -listallhardwareports 2>/dev/null | head -20

} | tee "$OUT"

echo ""
echo "Saved to $OUT"
