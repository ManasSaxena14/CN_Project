#!/bin/bash
# MAC 1 - Primary DNS + test client.   Run:  ./tests/test-mac1.sh
# Covers: Task A, Task B (server + client), Task D/E/F from a client, 6.3 failure
# simulations, Ext A/B (both DNS servers, TTL), Ext C (client blocked), Ext E (standby reachable)
source "$(dirname "$0")/lib.sh"
start_log mac1
section "Role check"; check_role "$MAC1_IP"
net_tests

section "Task B - DNS server on this Mac"
if pgrep -x dnsmasq >/dev/null || pgrep -f dns_server.py >/dev/null; then pass "DNS server process is running"
else fail "DNS server is not running" "sudo ./dns/start-dns.sh"; fi
a=$(dig +short +time=2 +tries=1 "@${TEST_DNS_LOCAL:-$MAC1_IP}" ${TEST_DNS_PORT:+-p $TEST_DNS_PORT} "$APP" | grep -E '^[0-9.]+$' | tail -1)
[ "$a" = "$EXPECTED_TARGET" ] && pass "this server answers $APP -> $a on its LAN IP" || fail "this server answers '${a:-nothing}' for $APP" "sudo ./dns/start-dns.sh"
if [ -f dns/dnsmasq.conf ]; then
  grep -q "address=/$APP/$EXPECTED_TARGET" dns/dnsmasq.conf && pass "dns/dnsmasq.conf: $APP -> $EXPECTED_TARGET (generated from config.env)" || warn "dns/dnsmasq.conf record differs from APP_TARGET_IP (cutover in progress?)"
  grep -q "local-ttl=$DNS_TTL" dns/dnsmasq.conf && pass "dns/dnsmasq.conf: local-ttl=$DNS_TTL" || fail "dnsmasq.conf TTL is not $DNS_TTL"
fi

client_tests
summary
