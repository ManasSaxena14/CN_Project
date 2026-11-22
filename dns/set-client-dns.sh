#!/bin/bash
# ───────────────────────────────────────────────────────────
# set-client-dns.sh — Configure client DNS for Phase 2 (Ext A)
#
# Sets BOTH Primary ($MAC1_IP) and Backup DNS ($BACKUP_DNS_IP).
# Also provides restore and status options.
#
# Usage:
#   sudo ./dns/set-client-dns.sh set      # set Primary + Backup DNS
#   sudo ./dns/set-client-dns.sh restore  # restore to automatic (DHCP)
#   ./dns/set-client-dns.sh status        # show current DNS configuration
# ───────────────────────────────────────────────────────────
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ ! -f "$PROJECT_DIR/config.env" ]; then
    echo "ERROR: config.env not found in $PROJECT_DIR"
    exit 1
fi

source "$PROJECT_DIR/config.env"

ACTION="${1:-set}"

# Detect Wi-Fi network service name
SERVICE=$(networksetup -listallnetworkservices 2>/dev/null | grep -Ei "^(Wi-Fi|AirPort)$" | head -1 || echo "Wi-Fi")

flush_cache() {
    echo "Flushing local DNS cache..."
    sudo dscacheutil -flushcache
    sudo killall -HUP mDNSResponder 2>/dev/null || true
    echo "✓ DNS cache flushed (mDNSResponder notified)"
}

case "$ACTION" in
    set)
        echo "============================================================"
        echo " Setting Client DNS (Phase 2 / Ext A)"
        echo " Service     : $SERVICE"
        echo " Primary DNS : $MAC1_IP (Mac 1)"
        echo " Backup DNS  : $BACKUP_DNS_IP (Mac 4)"
        echo "============================================================"

        sudo networksetup -setdnsservers "$SERVICE" "$MAC1_IP" "$BACKUP_DNS_IP"
        flush_cache

        echo ""
        echo "Active DNS servers on $SERVICE:"
        networksetup -getdnsservers "$SERVICE"

        echo ""
        echo "macOS Resolver Configuration (scutil --dns):"
        scutil --dns | grep -A 6 "resolver #1" || true

        echo ""
        echo "Testing resolution with dig:"
        dig +short app.$PROJECT_DOMAIN A 2>/dev/null || echo "(no answer yet - ensure DNS servers are running)"
        echo ""
        echo "✓ Client configured for dual-DNS failover (Ext A)."
        ;;

    restore)
        echo "============================================================"
        echo " Restoring Client DNS to DHCP Default"
        echo " Service: $SERVICE"
        echo "============================================================"

        sudo networksetup -setdnsservers "$SERVICE" Empty
        flush_cache

        echo ""
        echo "Current DNS status:"
        networksetup -getdnsservers "$SERVICE"
        echo "✓ Client restored to default network DNS."
        ;;

    status)
        echo "============================================================"
        echo " Current Client DNS Status"
        echo " Service: $SERVICE"
        echo "============================================================"
        echo "Configured servers on $SERVICE:"
        networksetup -getdnsservers "$SERVICE"
        echo ""
        echo "macOS Resolver table (scutil --dns):"
        scutil --dns | head -30
        ;;

    *)
        echo "Usage: sudo $0 {set|restore|status}"
        exit 1
        ;;
esac
