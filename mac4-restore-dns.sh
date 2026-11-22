#!/bin/bash
# ============================================================
#  Mac 4 – Restore DNS after the demo
#  Run this at the very end of the session.
# ============================================================

INTERFACE=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}')
echo "Restoring DNS on $INTERFACE to automatic (Empty)..."
sudo networksetup -setdnsservers "$INTERFACE" Empty
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null || true
echo "✓ DNS restored to default (DHCP/automatic)"
networksetup -getdnsservers "$INTERFACE"
