# DEMO SCRIPT – Computer Networks Phase 1
## 8 Steps | Exact Commands | Who Presents

> **IPs from config.env**  
> Mac 1 (DNS) `10.202.54.224` · Mac 2 (nginx) `10.81.95.225` · Mac 3 (Backend A) `10.81.95.70` · Mac 4 (Backend B / Test Client) `10.81.95.68`

---

## Step 1 – LAN: Show all 4 Macs are on the same subnet
**Presenter: Mac 1**

```bash
# On each Mac – show your IP
ipconfig getifaddr en0

# Ping each other from Mac 1
ping -c 3 10.81.95.225   # Mac 2
ping -c 3 10.81.95.70    # Mac 3
ping -c 3 10.81.95.68    # Mac 4
```

**What to show:** All in the same `/24` subnet. `evidence/01-lan/` screenshots.

---

## Step 2 – DNS: Private DNS resolves app.team1.test → Mac 2's IP
**Presenter: Mac 1 (runs DNS) + Mac 4 (client query)**

```bash
# Mac 1 – show the DNS server is running
ps aux | grep dns

# Mac 4 – query the private DNS
dig @10.202.54.224 app.team1.test
# Expected answer: 10.81.95.225  (MAC2_IP)

# also via system DNS (should work after client setup)
dig app.team1.test
```

**What to show:** Answer section = `10.81.95.225`. `evidence/02-dns/`.

---

## Step 3 – HTTPS: nginx terminates TLS, responds 200
**Presenter: Mac 2 (nginx) + Mac 4 (client)**

```bash
# Mac 4 – test HTTPS by domain name (not IP, not -k)
curl -v https://app.team1.test/api/status

# Show certificate details
curl -v --tlsv1.2 --tls-max 1.2 https://app.team1.test/api/status 2>&1 | grep -E "subject|issuer|SSL"
```

**What to show:** `HTTP/2 200`, `X-Backend: A` or `B`, certificate CN=app.team1.test. `evidence/03-https/`.

---

## Step 4 – Load Balancing: Requests alternate A ↔ B
**Presenter: Mac 4 (runs the loop)**

```bash
# Mac 4
for i in {1..10}; do
    echo -n "Request $i: "
    curl -s -D - -o /dev/null https://app.team1.test/api/status \
        | grep -i "^X-Backend:" | tr -d '\r'
done
```

**What to show:** `X-Backend: A` and `X-Backend: B` alternating. `evidence/04-load-balancing/`.

---

## Step 5 – Caching: ETag + 304 Not Modified
**Presenter: Mac 4**

```bash
# 1. First request → 200 + Cache-Control: max-age=60 + ETag
curl -sI https://app.team1.test/api/cache | grep -Ei "HTTP|cache-control|etag"

# 2. Capture ETag
ETAG=$(curl -sI https://app.team1.test/api/cache | grep -i "^etag:" | awk '{print $2}' | tr -d '\r')

# 3. Conditional request → 304 Not Modified
curl -sI -H "If-None-Match: $ETAG" https://app.team1.test/api/cache | grep "HTTP/"

# 4. ETags are identical across both backends
curl -sI http://10.81.95.70:3001/api/cache | grep -i etag
curl -sI http://10.81.95.68:3002/api/cache | grep -i etag
```

**What to show:** `304 Not Modified`, same ETag on A and B. `evidence/06-caching/`.

---

## Step 6 – Wireshark / tcpdump: Full packet capture
**Presenter: Mac 4**

```bash
# Already captured – open evidence/05-wireshark/full-flow.pcap in Wireshark

# Wireshark display filters (show one at a time):
#   dns                              → DNS query + answer (MAC2_IP)
#   tcp.flags.syn==1                 → 3-way handshake SYN/SYN-ACK to :443
#   tls.handshake                    → ClientHello(SNI), ServerHello, Certificate, CCS
#   tls.record.content_type==23      → Encrypted Application Data
```

**What to show:** Each screenshot from `evidence/05-wireshark/`. Point out: ephemeral port → 443, SNI=app.team1.test, cert, then encrypted data.

---

## Step 7 – Failure Demos: 5 failure scenarios
**Presenter: Mac 4 (runs mac4-failures.sh), all Macs cooperate**

| # | Failure | Expected output |
|---|---------|----------------|
| 1 | Wrong DNS server (8.8.8.8) | `NXDOMAIN` or no answer for app.team1.test |
| 2 | Wrong DNS IP (nonexistent) | Timeout / connection refused |
| 3 | One backend stopped (B) | All requests → `X-Backend: A` only |
| 4 | Both backends stopped | `502 Bad Gateway` from nginx |
| 5 | Wrong port (8080) | `Connection refused` |

```bash
# Mac 4
./mac4-failures.sh
# follow interactive prompts – coordinate over chat
```

**Evidence:** `evidence/07-failures/01-*.txt` through `05-*.txt`.

---

## Step 8 – Viva / Q&A: Architecture walkthrough
**Presenter: All 4 (each explains their machine)**

**Flow to narrate:**
```
Browser (Mac 4)
  → DNS query to Mac 1:53  → answer: Mac 2's IP
  → TCP SYN to Mac 2:443
  → TLS handshake (SNI: app.team1.test, cert from Mac 2)
  → HTTPS GET /api/status
  → nginx reverse-proxies to backend_pool (round-robin)
     → Mac 3:3001  or  Mac 4:3002
  → JSON response with X-Backend header
  → TLS record (content_type=23, encrypted) back to Mac 4
```

**Key questions to be ready for:**
- What is an ephemeral port? (random high port chosen by OS for this connection)
- 3-way handshake: SYN → SYN-ACK → ACK
- Why is HTTP traffic encrypted in tcpdump? (TLS wraps HTTP payload; only headers visible in TLS 1.2 handshake phase)
- What does ARP do? (resolves IP → MAC on the LAN before the first packet)
- TCP reliability: seq/ack numbers, retransmission on timeout, flow-control via window size

---

## Quick Evidence Index (find anything in < 30 s)

| Folder | Contents |
|--------|---------|
| `evidence/01-lan/` | ifconfig output, ping screenshots |
| `evidence/02-dns/` | dig output, DNS query proof |
| `evidence/03-https/` | curl -v output, cert details |
| `evidence/04-load-balancing/` | X-Backend alternating log |
| `evidence/05-wireshark/` | full-flow.pcap + screenshots (dns, syn, tls, app-data) |
| `evidence/06-caching/` | ETag + 304 responses |
| `evidence/07-failures/` | 01-05 failure text files |
