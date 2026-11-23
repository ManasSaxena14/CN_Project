#!/bin/bash
# =====================================================================
#  FINAL PRESENTATION - one script for all 4 Macs (role detected from
#  this Mac's IP vs config.env).  Follows the PDF's 11 demo steps.
#
#   ./demo.sh ready        start everything this Mac needs, reset to the
#                          clean starting state, then run this Mac's tests
#   ./demo.sh logs         this Mac's live log window (keep it on screen)
#   ./demo.sh 1 ... 10     this Mac's part of demo step N
#   ./demo.sh 9a|9b|9c|9e  Phase 2: backup DNS | TTL | firewall | edge cutover
#   ./demo.sh dns standby|normal   (Mac 1 / Mac 4) point app.team1.test at
#                          the standby edge / back to the primary edge
#   ./demo.sh cleanup      after the presentation: undo everything on this Mac
# =====================================================================
cd "$(dirname "$0")" || exit 1
ROOT="$PWD"
# shellcheck disable=SC1091
source "${TEST_CONFIG:-./config.env}"
APP="app.$PROJECT_DOMAIN"; P=""; [ "$HTTPS_PORT" != "443" ] && P=":$HTTPS_PORT"
URL="https://$APP$P"; CA="$ROOT/team1-ca.crt"
LOG="$ROOT/logs"; mkdir -p "$LOG"
PCAP=$(ls -t evidence/05-wireshark/*.pcap* 2>/dev/null | head -1)

B=$'\e[1m'; G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; C=$'\e[36m'; D=$'\e[2m'; N=$'\e[0m'
title() { echo; echo "${B}${C}=== STEP $1 ===${N}"; }
say()   { echo "${B}$*${N}"; }
tell()  { echo "${Y}  SAY:${N} $*"; }
ok()    { echo "  ${G}OK${N}  $*"; }
bad()   { echo "  ${R}!!${N}  $*"; }
show()  { echo "${D}\$ $*${N}"; }
pause() { echo; read -r -p "${C}>> $1  [Enter]${N} " _ </dev/tty; }
flush() { sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder 2>/dev/null; }
up()    { nc -z -G 2 "$1" "$2" >/dev/null 2>&1; }
pcap_edge() {  # edge IP from the capture's own DNS answer for app.<domain>
  [ -n "$PCAP" ] || return
  local id; id=$(tcpdump -nn -r "$PCAP" "udp dst port 53" 2>/dev/null | awk -v n="A? $APP." 'index($0,n){sub(/\+$/,"",$6); print $6; exit}')
  tcpdump -nn -r "$PCAP" "udp src port 53" 2>/dev/null | awk -v id="$id" '{x=$6; sub(/[*+]$/,"",x)} x==id{for(i=7;i<=NF;i++) if($i=="A"){v=$(i+1); sub(/[^0-9.]+$/,"",v); print v; exit}}'
}

IFACE=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}'); IFACE=${IFACE:-en0}
MYIP=$(ipconfig getifaddr "$IFACE" 2>/dev/null)
ROLE="${DEMO_ROLE:-}"
if [ -z "$ROLE" ]; then
  for i in 1 2 3 4; do v="MAC${i}_IP"; [ "${!v}" = "$MYIP" ] && ROLE="mac$i"; done
fi
if [ -z "$ROLE" ]; then
  bad "This Mac ($MYIP) is not in config.env."
  echo "     Fix config.env (Mac 1 commits it, everyone git pull), or run with DEMO_ROLE=macN"; exit 1
fi
is_client() { [ "$ROLE" = mac1 ] || [ "$ROLE" = mac4 ]; }
case $ROLE in
  mac1) NAME="Mac 1 - primary DNS + client" ;;
  mac2) NAME="Mac 2 - nginx edge (TLS + load balancer)" ;;
  mac3) NAME="Mac 3 - Backend A + standby edge" ;;
  mac4) NAME="Mac 4 - Backend B + backup DNS + main client" ;;
esac

# ---------------- service helpers ----------------
start_backend() {  # name port
  if up 127.0.0.1 "$2"; then ok "Backend $1 already running on :$2"; return; fi
  nohup env BACKEND_NAME="$1" BACKEND_PORT="$2" python3 -u backend.py >"$LOG/backend-$1.log" 2>&1 &
  sleep 1; up 127.0.0.1 "$2" && ok "Backend $1 started on :$2 (log: logs/backend-$1.log)" || bad "Backend $1 failed - see logs/backend-$1.log"
}
stop_backend() { local p; p=$(lsof -tiTCP:"$1" -sTCP:LISTEN 2>/dev/null); [ -n "$p" ] && kill $p; sleep 0.5; }
dns_start() {  # [target ip]
  local t="${1:-$APP_TARGET_IP}"
  sudo -v || return 1   # refresh sudo now: a password prompt in the background would hang
  sudo pkill -x dnsmasq 2>/dev/null; sleep 0.5
  sudo nohup ./dns/start-dns.sh --target "$t" >"$LOG/dns.log" 2>&1 &
  for _ in 1 2 3 4 5 6 7 8; do sleep 1
    [ "$(dig +short +time=1 +tries=1 @"$MYIP" "$APP" 2>/dev/null | tail -1)" = "$t" ] && { ok "DNS on this Mac answers $APP -> $t (TTL ${DNS_TTL}s)"; return; }
  done; bad "DNS did not come up - see logs/dns.log"
}
edge_ok() { curl -s -m 4 --cacert "$CA" --resolve "$APP:$HTTPS_PORT:$1" -o /dev/null -w '%{http_code}' "$URL/api/status" 2>/dev/null | grep -q 200; }
fw_on()  { sudo ./firewall/backend-firewall.sh apply; }
fw_off() { if [ -f /etc/pf.anchors/team1-backend ]; then sudo ./firewall/backend-firewall.sh remove >/dev/null && ok "firewall removed (clean start for Ext C)"; else ok "firewall off (clean start for Ext C)"; fi; }
client_ready() {
  sudo ./dns/set-client-dns.sh set >/dev/null 2>&1; flush
  ok "client DNS -> $MAC1_IP (primary) + $BACKUP_DNS_IP (backup)"
  local rc; curl -s -m 6 -o /dev/null "$URL/api/status"; rc=$?
  if [ $rc -eq 60 ]; then say "  CA not trusted yet - installing it"; ./mac4-client-setup.sh team1-ca.crt >/dev/null && ok "CA trusted"; fi
}

# ---------------- ready / logs / cleanup ----------------
cmd_ready() {
  say "Getting $NAME ready  (IP $MYIP)"
  git fetch -q 2>/dev/null && [ "$(git rev-list --count HEAD..@{u} 2>/dev/null)" != 0 ] && bad "you are behind GitHub - run: git pull  (then ./demo.sh ready again)"
  sudo -v || exit 1
  case $ROLE in
    mac1) dns_start; client_ready ;;
    mac2) ./nginx-script.sh start >/dev/null && edge_ok "$MYIP" && ok "nginx edge serving https://$APP on $MYIP:$HTTPS_PORT" || bad "nginx not serving - run ./nginx-script.sh start" ;;
    mac3) start_backend A "$BACKEND_A_PORT"; fw_off
          if edge_ok "$MYIP"; then ok "standby edge already running"
          elif [ -f "$HOME/cn-phase1/edge/nginx/certs/app.$PROJECT_DOMAIN.key" ]; then ./mac3-standby-edge.sh start >/dev/null 2>&1; edge_ok "$MYIP" && ok "standby edge started (for Ext E)" || bad "standby edge failed: ./mac3-standby-edge.sh start"
          else bad "edge cert not imported (needed for Ext E): Mac 2 ./mac2-export-certs.sh -> AirDrop -> ./mac2-import-certs.sh <tgz>"; fi ;;
    mac4) start_backend B "$BACKEND_B_PORT"; fw_off; dns_start; client_ready
          if [ -z "$PCAP" ]; then bad "no capture yet: sudo ./mac4-task-g-capture.sh"
          elif [ "$(pcap_edge)" != "$MAC2_IP" ]; then bad "capture is from an old network (edge $(pcap_edge)) - recapture so the IPs match today: sudo ./mac4-task-g-capture.sh"
          else ok "saved capture matches today's network: $PCAP"; fi ;;
  esac
  echo; say "Self-test:"; is_client && echo "${D}  (Mac 1 and Mac 4: run tests one after the other, not at the same time)${N}"
  ./tests/test-"$ROLE".sh | tail -8
  echo; say "Ready. Keep a second tab open with:  ./demo.sh logs"
}
cmd_logs() {
  case $ROLE in
    mac1) say "Live DNS queries (dnsmasq)  - Ctrl+C to stop"; touch "$LOG/dns.log"; tail -n 5 -f "$LOG/dns.log" | grep --line-buffered -E "query|reply|config|forwarded|cached" ;;
    mac2) say "Live edge log: client ip:port, TLS, request, status, which backend - Ctrl+C to stop"; ./nginx-script.sh logs ;;
    mac3) say "Live Backend A log - Ctrl+C to stop"; touch "$LOG/backend-A.log"; tail -f "$LOG/backend-A.log" ;;
    mac4) say "Live Backend B log + backup DNS queries - Ctrl+C to stop"; touch "$LOG/backend-B.log"
          touch "$LOG/dns.log"; tail -n 5 -f "$LOG/backend-B.log" "$LOG/dns.log" | grep --line-buffered -vE "^$|compile time|started, version" ;;
  esac
}
cmd_cleanup() {
  sudo -v || exit 1
  is_client && { sudo ./dns/set-client-dns.sh restore >/dev/null 2>&1; flush; ok "client DNS back to automatic"; }
  case $ROLE in
    mac1) sudo pkill -x dnsmasq; ok "DNS stopped" ;;
    mac2) ./nginx-script.sh stop ;;
    mac3) fw_off; ./mac3-standby-edge.sh stop >/dev/null 2>&1; ok "standby edge stopped"; stop_backend "$BACKEND_A_PORT"; ok "Backend A stopped" ;;
    mac4) fw_off; sudo pkill -x dnsmasq; ok "backup DNS stopped"; stop_backend "$BACKEND_B_PORT"; ok "Backend B stopped" ;;
  esac
}
cmd_dns() {
  is_client || { bad "only Mac 1 and Mac 4 run DNS"; exit 1; }
  sudo -v || exit 1
  case "${1:-}" in
    standby) dns_start "$STANDBY_EDGE_IP" ;;
    normal)  dns_start "$APP_TARGET_IP" ;;
    stop)    sudo pkill -x dnsmasq; ok "DNS stopped on this Mac" ;;
    *) echo "usage: ./demo.sh dns standby|normal|stop" ;;
  esac
}

# ---------------- the 11 steps ----------------
client_only() { is_client || { echo "  This step is presented from ${B}Mac 4${N} (client). $1"; return 1; }; }

step1() { title "1 - Topology and IP / service inventory"
  printf "  ${B}%-6s %-40s %-16s %s${N}\n" Mac Role IP "Service : port"
  printf "  %-6s %-40s %-16s %s\n" "Mac 1" "Primary DNS (dnsmasq) + test client" "$MAC1_IP" "UDP 53" \
    "Mac 2" "Edge: nginx TLS termination + LB" "$MAC2_IP" "TCP 443" \
    "Mac 3" "Backend A + standby edge (Ext E)" "$MAC3_IP" "TCP 3001 (+443 standby)" \
    "Mac 4" "Backend B + backup DNS + test client" "$MAC4_IP" "TCP 3002, UDP 53"
  echo; echo "  DNS records: $APP, api.$PROJECT_DOMAIN -> $APP_TARGET_IP  (TTL ${DNS_TTL}s)"
  echo "  Flow: client -> DNS (Mac 1, backup Mac 4) -> HTTPS to Mac 2 (nginx) -> Backend A (Mac 3) or B (Mac 4)"
  echo "  Cloud: DNS = Route 53 | nginx = AWS ALB | backends = EC2 target group | firewall = security group"
  echo; ok "this Mac: $NAME"
  [ "$ROLE" = mac1 ] && { open ARCHITECTURE.md 2>/dev/null; tell "Point at the diagram: clients only ever talk to Mac 2; DNS just gives them Mac 2's IP."; }
}
step2() { title "2 - All machines on the private LAN"
  show "ipconfig getifaddr $IFACE"; echo "  this Mac ($ROLE): $MYIP   mask $(ipconfig getoption "$IFACE" subnet_mask)   gateway $(route -n get default | awk '/gateway:/{print $2}')"
  for i in 1 2 3 4; do v="MAC${i}_IP"; [ "${!v}" = "$MYIP" ] && continue
    show "ping -c 3 ${!v}"; ping -c 3 -t 4 "${!v}" | tail -2 | sed 's/^/  /'; done
  tell "Same subnet, same gateway, every Mac answers ICMP - layer 3 works before any service."
}
step3() { title "3 - Resolve the private name from a client"
  client_only "Mac 1: keep './demo.sh logs' visible - the query appears live." || return
  flush; show "dig $APP"
  dig "$APP" | grep -E "status:|^$APP|SERVER:|Query time" | sed 's/^/  /'
  tell "Answer is Mac 2's IP ($APP_TARGET_IP), from OUR server on UDP 53 (SERVER line), TTL ${DNS_TTL}s."
  tell "DNS only finds the address - no connection to the app exists yet."
}
step4() { title "4 - HTTPS by name, no certificate warnings"
  if [ "$ROLE" = mac2 ]; then
    show "openssl x509 -in <edge cert> -noout -subject -issuer -ext subjectAltName -dates"
    openssl x509 -in "$HOME/cn-phase1/edge/nginx/certs/app.$PROJECT_DOMAIN.crt" -noout -subject -issuer -ext subjectAltName -dates | sed 's/^/  /'
    tell "Cert for app/api.team1.test, signed by our Team1 Local CA. TLS ends HERE; nginx -> backends is plain HTTP."
    tell "Handshake: ClientHello (SNI) -> ServerHello -> Certificate -> key exchange -> Finished."; return; fi
  client_only "" || return
  show "curl -v $URL/api/status"
  curl -sv "$URL/api/status" 2>&1 | grep -E "Connected to|SSL connection|ALPN: server|subject:|issuer:|verify ok|^< HTTP|^< x-backend|^< x-edge|^\{" | sed 's/^/  /'
  open -a Safari "$URL" 2>/dev/null
  tell "No -k: the certificate is verified against our CA, installed in this Mac's trust store. Safari shows the padlock, no IP in the URL."
}
step5() { title "5 - Load balancing across both backends"
  client_only "Mac 2: './demo.sh logs' shows upstream= alternating." || return
  show "for i in \$(seq 8); do curl -s -D - -o /dev/null $URL/api/status | grep -i x-backend; done"
  for i in 1 2 3 4 5 6 7 8; do curl -s -m 5 -D - -o /dev/null "$URL/api/status" | tr -d '\r' | awk -v i=$i '
    tolower($1)=="x-backend:"{b=$2} tolower($1)=="x-upstream:"{u=$2} END{printf "  request %d -> X-Backend: %s   (upstream %s)\n", i, b, u}'; done
  tell "Round-robin: one name, one IP, two servers. The client never learns the backend IPs."
}
step6() { title "6 - Wireshark: DNS, TCP and TLS"
  [ "$ROLE" = mac4 ] || { echo "  Presented on ${B}Mac 4${N} from the saved capture."; return; }
  [ -n "$PCAP" ] || { bad "no capture: sudo ./mac4-task-g-capture.sh"; return; }
  say "  Saved capture: $PCAP"
  local qid edge sport
  qid=$(tcpdump -nn -r "$PCAP" "udp dst port 53" 2>/dev/null | awk -v n="A? $APP." 'index($0,n){sub(/\+$/,"",$6); print $6; exit}')
  edge=$(pcap_edge)
  echo "  -- DNS: client ephemeral port -> 53/UDP, answer = edge IP $edge"
  tcpdump -nn -r "$PCAP" "udp port 53" 2>/dev/null | awk -v id="$qid" '$6==id || $6==id"+" || $6==id"*"' | head -2 | sed 's/^/     /'
  sport=$(tcpdump -nn -r "$PCAP" "dst host $edge and dst port 443 and tcp[tcpflags] & tcp-syn != 0" 2>/dev/null | head -1 | awk '{split($3,a,"."); print a[5]}')
  echo "  -- TCP 3-way handshake, then TLS (client port $sport -> $edge:443):"
  tcpdump -nn -r "$PCAP" "host $edge and port $sport" 2>/dev/null | head -6 | awk '{
     lab="     "; if(NR==1)lab="SYN  "; if(NR==2)lab="S-ACK"; if(NR==3)lab="ACK  "; if(NR==4)lab="TLS  ";
     printf "     %s %s %s %s %s %s\n", lab, $3, $4, $5, $6, $7}'
  [ "$edge" != "$MAC2_IP" ] && echo "  ${D}(capture was taken on an earlier network, edge was $edge - same flow, different addresses)${N}"
  open -a Wireshark "$PCAP" 2>/dev/null
  echo; echo "  Wireshark filters, in this order:"
  echo "     dns                            query + answer = $edge"
  echo "     ip.addr==$edge && tcp.flags.syn==1    SYN / SYN-ACK  (show ports + seq/ack)"
  echo "     tls.handshake                  ClientHello (SNI) / ServerHello / Certificate / ChangeCipherSpec"
  echo "     tls.record.content_type==23    Application Data = encrypted HTTP"
  tell "Ephemeral port -> 53/UDP for DNS, ephemeral -> 443/TCP for HTTPS. HTTP itself is encrypted, so we read headers with curl -v."
}
step7() { title "7 - HTTP headers and caching (304)"
  client_only "Mac 3 explains: /api/cache has the same ETag on A and B." || return
  show "curl -I $URL/api/cache"
  local h etag; h=$(curl -s -I "$URL/api/cache" | tr -d '\r'); echo "$h" | sed 's/^/  /'
  etag=$(echo "$h" | awk -F': ' 'tolower($1)=="etag"{print $2}')
  pause "Now a conditional request with that ETag"
  show "curl -I -H 'If-None-Match: $etag' $URL/api/cache"
  curl -s -I -H "If-None-Match: $etag" "$URL/api/cache" | tr -d '\r' | sed 's/^/  /'
  tell "Fresh hit: within max-age=60 the browser does not ask at all. Conditional: If-None-Match -> 304, headers only, no body. Full: 200 + body."
}
step8() { title "8 - Fail Backend A, service continues"
  case $ROLE in
    mac4) say "  Live requests every second. Mac 3 will stop Backend A. Ctrl+C here when done."; ./mac2-ha-demo.sh watch ;;
    mac3) pause "Stop Backend A now? (Mac 4 should be running './demo.sh 8' first)"
          stop_backend "$BACKEND_A_PORT"; up 127.0.0.1 "$BACKEND_A_PORT" && bad "still running" || ok "Backend A STOPPED"
          tell "Requests keep succeeding via B: nginx got 'connection refused', retried on B, and benched A for 10 s."
          pause "Restart Backend A?"; start_backend A "$BACKEND_A_PORT"
          tell "After its 10 s fail_timeout nginx tries A again - load balancing resumes, no config change." ;;
    mac2) echo "  Watch './demo.sh logs': upstream= shows only Mac 4 while A is down."
          tell "Passive health check: max_fails=1 fail_timeout=10s + proxy_next_upstream. Remaining single point of failure: this edge." ;;
    *) echo "  Mac 3 stops Backend A, Mac 4 shows requests still succeeding." ;;
  esac
}
step9() { title "9 - Phase 2: DNS and resilience"
  echo "  9a  backup DNS failover (Ext A)    Mac 1 + Mac 4"
  echo "  9b  TTL and caching (Ext B)        Mac 4 runs it, Mac 1 + Mac 4 switch DNS"
  echo "  9c  backend firewall (Ext C)       Mac 3 + Mac 4 apply, Mac 1 + Mac 2 verify"
  echo "  9e  edge cutover (Ext E)           Mac 4 watches, Mac 1 + Mac 4 switch DNS"
  echo "  (Ext D failover was step 8)    Run: ./demo.sh 9a  etc."
}
step9a() { title "9a - Backup DNS failover (Ext A)"
  case $ROLE in
    mac1) pause "Stop the PRIMARY DNS on this Mac?"; sudo pkill -x dnsmasq; ok "primary DNS stopped"
          tell "Name resolution is a separate service from the app: clients now need the backup."
          pause "Restart the primary DNS?"; dns_start ;;
    mac4) pause "Run AFTER Mac 1 has stopped its DNS"; flush
          show "dig +time=2 +tries=1 $APP"; dig +time=2 +tries=1 "$APP" | grep -E "status:|^$APP|SERVER:" | sed 's/^/  /'
          show "curl -s $URL/api/status"; curl -s -m 8 "$URL/api/status" | sed 's/^/  /'; echo
          tell "SERVER is now Mac 4 ($BACKUP_DNS_IP): the backup has identical records, so the service keeps working."
          tell "DNS failure = names stop resolving. App failure = names resolve but the service is down." ;;
    *) echo "  Mac 1 stops its DNS, Mac 4 shows the backup answering." ;;
  esac
}
step9b() { title "9b - TTL and caching (Ext B)"
  case $ROLE in
    mac4) echo "  When the script asks you to change the record, in another tab on THIS Mac run:  ${B}./demo.sh dns standby${N}"
          echo "  and on Mac 1:  ${B}./demo.sh dns standby${N}.   Afterwards both run:  ${B}./demo.sh dns normal${N}"
          pause "Start the TTL demo"; ./dns/ttl-demo.sh ;;
    mac1) echo "  When Mac 4 asks: ${B}./demo.sh dns standby${N}   ... at the end: ${B}./demo.sh dns normal${N}" ;;
    *) echo "  Mac 4 runs the TTL demo; Mac 1 and Mac 4 switch DNS records." ;;
  esac
}
step9c() { title "9c - Backend isolation with pf firewall (Ext C)"
  direct() { for t in "3:$MAC3_IP:$BACKEND_A_PORT" "4:$MAC4_IP:$BACKEND_B_PORT"; do IFS=: read -r m ip port <<< "$t"
      [ "$ip" = "$MYIP" ] && continue; show "curl -m 4 http://$ip:$port/api/status"
      if curl -s -m 4 -o /dev/null "http://$ip:$port/api/status"; then echo "  Mac $m:$port -> ${G}REACHABLE${N}"; else echo "  Mac $m:$port -> ${R}BLOCKED (timeout)${N}"; fi; done; }
  case $ROLE in
    mac3|mac4) pause "Apply the firewall on this Mac? (Mac 1 shows 'before' first)"; fw_on
          tell "Only the edges ($MAC2_IP and standby $STANDBY_EDGE_IP) may reach this backend port; everyone else is silently dropped."
          echo "  Remove later with ./demo.sh cleanup (or: sudo ./firewall/backend-firewall.sh remove)" ;;
    mac1) say "  BEFORE (firewall off):"; direct
          pause "Mac 3 and Mac 4 apply their firewall now, then press Enter"
          say "  AFTER:"; direct
          show "curl -s -o /dev/null -w '%{http_code}' $URL/api/status"; echo "  through the edge -> $(curl -s -m 6 -o /dev/null -w '%{http_code}' "$URL/api/status")"
          tell "Clients can no longer bypass the edge, but the site still works through it - like a security group that only allows the ALB." ;;
    mac2) say "  The edge is still allowed:"; for t in "$MAC3_IP:$BACKEND_A_PORT" "$MAC4_IP:$BACKEND_B_PORT"; do
            show "curl http://$t/api/status"; curl -s -m 4 "http://$t/api/status" | sed 's/^/  /'; echo; done ;;
  esac
}
step9e() { title "9e - DNS-based edge cutover (Ext E)"
  case $ROLE in
    mac4) echo "  Leave this running. In ANOTHER tab on this Mac: ${B}./demo.sh dns standby${N}  (Mac 1 does the same)."
          echo "  Watch X-EDGE stay mac2-primary until the ${DNS_TTL}s TTL expires, then flip to mac3-standby."
          echo "  To restore, both run: ${B}./demo.sh dns normal${N}.   Ctrl+C here when done."; pause "Start watching"; ./mac2-edge-watch.sh ;;
    mac1) echo "  When Mac 4 is watching:  ${B}./demo.sh dns standby${N}   ...then later:  ${B}./demo.sh dns normal${N}"
          tell "The DNS server changes instantly, but clients keep the cached answer for up to ${DNS_TTL}s. Keep the old edge running for one TTL - that's why you lower TTL before a migration." ;;
    mac3) edge_ok "$MYIP" && ok "standby edge on this Mac is serving (X-Edge: mac3-standby)" || bad "standby not running: ./mac3-standby-edge.sh start" ;;
    mac2) tell "Both edges serve during the switch, so no request fails. Faster failover would need a floating IP (VRRP) or a managed LB." ;;
  esac
}
step10() { title "10 - Diagnose the injected fault"
  echo "  Order: DNS -> IP -> TCP -> TLS -> HTTP. Say each layer out loud."
  case $ROLE in
    mac4|mac1) ./troubleshoot/diagnose.sh ;;
    mac2) edge_ok "$MYIP" && ok "nginx is serving HTTPS on $MYIP:$HTTPS_PORT" || bad "nginx NOT serving: ./nginx-script.sh start"
          show "tail -5 error.log"; tail -5 "$HOME/cn-phase1/edge/nginx/logs/error.log" | sed 's/^/  /'
          for t in "$MAC3_IP:$BACKEND_A_PORT" "$MAC4_IP:$BACKEND_B_PORT"; do up "${t%:*}" "${t#*:}" && ok "backend $t reachable" || bad "backend $t NOT reachable"; done ;;
    mac3) up 127.0.0.1 "$BACKEND_A_PORT" && ok "Backend A running" || bad "Backend A down: ./demo.sh ready"
          [ -f /etc/pf.anchors/team1-backend ] && echo "  firewall is ON - check it allows $MAC2_IP: sudo ./firewall/backend-firewall.sh status" ;;
  esac
  echo "  Runbook: troubleshoot/RUNBOOK.md"
}

case "${1:-}" in
  ready) cmd_ready ;; logs) cmd_logs ;; cleanup) cmd_cleanup ;; dns) cmd_dns "${2:-}" ;;
  1|2|3|4|5|6|7|8|9|10) "step$1" ;; 9a|9b|9c|9e) "step$1" ;;
  11) title "11 - Individual viva"; echo "  Answer from understanding. Revise: MAC2-PHASE2.md, troubleshoot/RUNBOOK.md, PHASE2-REPORT.md" ;;
  *) sed -n '2,15p' "$0"; echo; echo "  This Mac: $NAME ($MYIP)" ;;
esac
