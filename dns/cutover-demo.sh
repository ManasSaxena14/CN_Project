#!/bin/bash
# ───────────────────────────────────────────────────────────
# cutover-demo.sh — Phase 2 Extension E: Active-Passive Edge Cutover
#
# Demonstrates switching app.team1.test from Primary Edge ($MAC2_IP)
# to Standby Edge ($STANDBY_EDGE_IP) on both DNS servers.
#
# Usage:
#   ./dns/cutover-demo.sh cutover   # switch DNS to Standby Edge
#   ./dns/cutover-demo.sh restore   # switch DNS back to Primary Edge
#   ./dns/cutover-demo.sh status    # check where DNS currently points
# ───────────────────────────────────────────────────────────
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/config.env"

ACTION="${1:-status}"
DOMAIN="app.$PROJECT_DOMAIN"

case "$ACTION" in
    cutover)
        echo "============================================================"
        echo "  EXT E: INITIATING CUTOVER TO STANDBY EDGE (Mac 3)"
        echo "============================================================"
        echo "  Switching $DOMAIN target to: $STANDBY_EDGE_IP"
        echo "  Record TTL: ${DNS_TTL:-30}s"
        echo "============================================================"
        echo ""
        echo "To execute cutover on Mac 1:"
        echo "  sudo $SCRIPT_DIR/start-dns.sh --target $STANDBY_EDGE_IP"
        echo ""
        echo "To execute cutover on Mac 4 (Backup DNS):"
        echo "  sudo ./dns/start-dns.sh --target $STANDBY_EDGE_IP"
        echo ""
        echo "------------------------------------------------------------"
        echo "VIVA NOTE — Active-Passive Cutover Dynamics:"
        echo "• When DNS changes, existing clients with active cache still connect"
        echo "  to Mac 2 (Primary Edge) for the remaining TTL window (up to 30s)."
        echo "• New clients or clients whose TTL has expired immediately connect"
        echo "  to Mac 3 (Standby Edge)."
        echo "• This creates a 'graceful drain' where traffic transitions gradually"
        echo "  without dropping active TCP connections."
        echo "------------------------------------------------------------"
        ;;

    restore)
        echo "============================================================"
        echo "  EXT E: RESTORING TARGET TO PRIMARY EDGE (Mac 2)"
        echo "============================================================"
        echo "  Switching $DOMAIN target back to: $MAC2_IP"
        echo "============================================================"
        echo ""
        echo "To restore on Mac 1 and Mac 4:"
        echo "  sudo $SCRIPT_DIR/start-dns.sh --target $MAC2_IP"
        ;;

    status)
        echo "============================================================"
        echo "  EXT E: DNS RESOLUTION STATUS"
        echo "============================================================"
        echo "Querying Primary DNS ($MAC1_IP):"
        dig +short @"$MAC1_IP" "$DOMAIN" 2>/dev/null || echo "(Mac 1 unreachable)"
        echo ""
        echo "Querying Backup DNS ($BACKUP_DNS_IP):"
        dig +short @"$BACKUP_DNS_IP" "$DOMAIN" 2>/dev/null || echo "(Mac 4 unreachable)"
        ;;

    *)
        echo "Usage: $0 {cutover|restore|status}"
        exit 1
        ;;
esac
