# 🏗️ ARCHITECTURE — Computer Networks Phase 1

> Private DNS + HTTPS Edge + 2 Backends on a single Wi-Fi LAN

---

## 1. Network Topology

```
┌──────────────────────────────────────────────────────────────────────┐
│               Wi-Fi LAN — OnePlus 11R 5G  (10.202.54.x)             │
│                                                                      │
│   ┌─────────────┐    ┌──────────────────┐    ┌─────────────────┐    │
│   │   MAC 1      │    │     MAC 2        │    │     MAC 3       │    │
│   │  DNS Server  │    │  nginx HTTPS     │    │   Backend A     │    │
│   │  (dnsmasq)   │    │  Edge / LB       │    │   :3001         │    │
│   │  UDP :53     │    │  TCP :443 (TLS)  │    │   HTTP          │    │
│   │              │    │                  │    │                 │    │
│   │ 10.202.54.224│    │  10.81.95.225    │    │  10.81.95.70    │    │
│   └──────┬───────┘    └────────┬─────────┘    └────────┬────────┘    │
│          │                     │                       │             │
│          │         ┌───────────┴───────────┐           │             │
│          │         │  OnePlus 11R Hotspot   │           │             │
│          │         │     10.202.54.86      │           │             │
│          │         └───────────┬───────────┘           │             │
│          │                     │                       │             │
│   ┌──────┴──────────────────────────────────────┬──────┘             │
│   │                                              │                   │
│   │                                    ┌─────────┴─────────┐        │
│   │                                    │     MAC 4         │        │
│   │                                    │   Backend B       │        │
│   │                                    │   :3002           │        │
│   │                                    │   HTTP            │        │
│   │                                    │                   │        │
│   │                                    │  10.81.95.68      │        │
│   │                                    └───────────────────┘        │
│   │                                                                  │
└──────────────────────────────────────────────────────────────────────┘
```

### Cloud Equivalents

| LAN Role           | Component      | AWS Equivalent        | Why                                                       |
|--------------------|----------------|-----------------------|-----------------------------------------------------------|
| Mac 1 – DNS        | dnsmasq        | **Amazon Route 53**   | Authoritative DNS; maps names → IPs                       |
| Mac 2 – HTTPS Edge | nginx reverse proxy | **ALB (Application Load Balancer)** | TLS termination, L7 routing, round-robin to backends |
| Mac 3 – Backend A  | Python HTTP    | **EC2 instance #1**   | Application server behind the LB                          |
| Mac 4 – Backend B  | Python HTTP    | **EC2 instance #2**   | Second app server for redundancy / load sharing           |
| OnePlus hotspot    | DHCP + NAT     | **VPC + IGW**         | Private network + internet gateway                        |

---

## 2. IP / Service Table

| Mac   | Role              | IP (en0)        | Ports             | Software         |
|-------|-------------------|-----------------|-------------------|------------------|
| Mac 1 | DNS Server        | `10.202.54.224` | UDP 53            | dnsmasq 2.93     |
| Mac 2 | HTTPS Edge / LB   | `10.81.95.225`  | TCP 443 (TLS)     | nginx + self-signed cert |
| Mac 3 | Backend A         | `10.81.95.70`   | TCP 3001 (HTTP)   | Python `backend.py` |
| Mac 4 | Backend B         | `10.81.95.68`   | TCP 3002 (HTTP)   | Python `backend.py` |

> [!IMPORTANT]
> **IPs are placeholders for Mac 2–4** until you collect them from your teammates.
> Mac 1's IP (`10.202.54.224`) is confirmed. Update `config.env` after collecting the others.

### DNS Records Served

| Record              | Type | Value           | TTL  |
|---------------------|------|-----------------|------|
| `app.team1.test`    | A    | `10.81.95.225`  | 60 s |
| `api.team1.test`    | A    | `10.81.95.225`  | 60 s |
| `*.test` (other)    | —    | NXDOMAIN        | —    |
| everything else     | —    | forwarded to `8.8.8.8` | —  |

---

## 3. Request-Flow Diagram

A client on the LAN types `curl https://app.team1.test/api/status`:

```
Client Mac                Mac 1 (DNS)         Mac 2 (nginx)       Mac 3 or 4 (Backend)
    │                         │                     │                      │
    │  1. DNS Query (UDP 53)  │                     │                      │
    │  "A app.team1.test?"    │                     │                      │
    │────────────────────────►│                     │                      │
    │                         │                     │                      │
    │  2. DNS Response        │                     │                      │
    │  "10.81.95.225, TTL=60" │                     │                      │
    │◄────────────────────────│                     │                      │
    │                         │                     │                      │
    │  3. TCP 3-way Handshake (SYN → SYN-ACK → ACK)│                      │
    │────────────────────────────────────────────────►                      │
    │                         │                     │                      │
    │  4. TLS Handshake       │                     │                      │
    │  (ClientHello, certs,   │                     │                      │
    │   key exchange, Finished)                     │                      │
    │◄──────────────────────────────────────────────►                      │
    │                         │                     │                      │
    │  5. HTTP GET /api/status│(inside TLS tunnel)  │                      │
    │────────────────────────────────────────────────►                      │
    │                         │                     │                      │
    │                         │  6. nginx proxies   │                      │
    │                         │  HTTP GET to backend│                      │
    │                         │  (round-robin)      │                      │
    │                         │     ────────────────────────────────────────►
    │                         │                     │                      │
    │                         │  7. Backend responds│ {"backend":"A",      │
    │                         │                     │  "status":"ok"}      │
    │                         │     ◄────────────────────────────────────────
    │                         │                     │                      │
    │  8. nginx returns response (via TLS)          │                      │
    │◄────────────────────────────────────────────────                      │
    │                         │                     │                      │
```

**What each step proves in the viva:**

| Step | What Happens | Protocol/Layer |
|------|-------------|---------------|
| 1–2 | Name → IP translation | DNS (Application L7, transported over UDP L4) |
| 3 | Reliable connection setup | TCP (Transport L4) |
| 4 | Encryption & server identity | TLS (between L4 and L7) |
| 5 | Application request | HTTP/1.1 (Application L7) |
| 6–7 | Reverse proxy + load balancing | HTTP proxy (Application L7) |
| 8 | Encrypted response back | HTTPS (all layers) |

---

## 4. OSI / TCP-IP Layer Mapping

```
┌─────────────────────────────────────────────────────────────────────┐
│                     OSI MODEL vs TCP/IP MODEL                       │
├───────┬───────────────┬──────────────┬──────────────────────────────┤
│ OSI # │ OSI Layer     │ TCP/IP Layer │ What's Here in Our Project   │
├───────┼───────────────┼──────────────┼──────────────────────────────┤
│   7   │ Application   │              │ HTTP GET /api/status         │
│   6   │ Presentation  │ Application  │ TLS encryption/decryption    │
│   5   │ Session       │              │ TLS session, keep-alive      │
├───────┼───────────────┼──────────────┼──────────────────────────────┤
│   4   │ Transport     │ Transport    │ TCP :443, UDP :53            │
│       │               │              │ 3-way handshake, port numbers│
├───────┼───────────────┼──────────────┼──────────────────────────────┤
│   3   │ Network       │ Internet     │ IP addresses (10.202.54.224…)│
│       │               │              │ Routing via gateway 10.202.54.86│
├───────┼───────────────┼──────────────┼──────────────────────────────┤
│   2   │ Data Link     │ Network      │ MAC addresses, Wi-Fi frames  │
│   1   │ Physical      │ Access       │ 802.11 radio (Wi-Fi)         │
└───────┴───────────────┴──────────────┴──────────────────────────────┘
```

### Where each project component sits:

| Component | Primary Layer | Protocol | Port |
|-----------|--------------|----------|------|
| DNS query/response | L7 (App) carried over L4 (UDP) | DNS over UDP | 53 |
| TCP connection to nginx | L4 (Transport) | TCP | 443 |
| TLS handshake | L5-L6 (Session/Presentation) | TLS 1.2/1.3 | — |
| HTTP request/response | L7 (Application) | HTTP/1.1 | — |
| IP routing between Macs | L3 (Network) | IPv4 | — |
| Wi-Fi frames | L2 (Data Link) | 802.11n (2.4 GHz) | — |

---

## 5. Why `.test` and Not `.local`?

| TLD | Behaviour | Problem |
|-----|-----------|---------|
| `.local` | Reserved by **mDNS / Bonjour** (RFC 6762). macOS intercepts `.local` queries and sends them via multicast, **not** to our DNS server. | Our `dig` would never reach Mac 1. |
| `.test` | Reserved by **IANA for testing** (RFC 6761). No browser, OS, or ISP will resolve it. No collision risk. | Perfect for private DNS experiments. |

---

## 6. Viva Key Concepts

### DNS vs TCP Connection
- **DNS** (Layer 7/UDP) translates a *name* to an *IP address*. It's a separate step that happens *before* any TCP connection.
- **TCP** (Layer 4) creates a reliable byte-stream between two IPs. It doesn't know or care about domain names.
- **Proof**: Failure Demo (a) — breaking DNS stops name resolution, but `ping <IP>` still works because IP/ICMP don't need DNS.

### UDP Port 53
- DNS uses **UDP** because queries are small (< 512 bytes) and stateless — one question, one answer. No handshake overhead.
- TCP is used for DNS only when the response is > 512 bytes (zone transfers, DNSSEC).
- Our dnsmasq listens on `0.0.0.0:53` (all interfaces, UDP).

### TTL (Time To Live)
- Our DNS responses include `TTL=60` → the client (and any intermediate cache) may reuse this answer for 60 seconds without re-querying.
- **Viva question**: "What happens if you change the DNS record?" → Clients won't see the change for up to 60 s (or until they flush: `sudo dscacheutil -flushcache`).

### Why `dig` and `curl` Can Disagree
- `dig` talks **directly to the DNS server you specify** (`@10.202.54.224`) — it bypasses the OS cache.
- `curl` (and browsers) use the **OS resolver** (`/etc/resolv.conf` or `networksetup` DNS), which has its own cache (`mDNSResponder` on macOS).
- So after changing a DNS record, `dig @server` shows the new IP immediately, but `curl` may still use the old cached IP until you flush.

### NXDOMAIN
- When our DNS gets a query for `random.test`, it returns **NXDOMAIN** (Non-Existent Domain) — "this name does not exist in my zone."
- For `google.com` (not `.test`), it **forwards** the query to `8.8.8.8` so internet still works.

---

## 7. File Map

```
CN_Project/
├── config.env                  # All IPs — single source of truth
├── setup.sh                    # Generates role-specific files on each Mac
├── backend.py                  # Shared backend code (Mac 3 & 4)
├── nginx-script.sh             # nginx config generator (Mac 2)
├── test-phase1.sh              # End-to-end test script
│
├── dns/
│   ├── dnsmasq.conf            # dnsmasq configuration (recommended)
│   ├── start-dns.sh            # Start DNS (dnsmasq or python)
│   ├── verify-dns.sh           # Verify DNS records
│   └── set-client-dns.sh       # Point client DNS → Mac 1 / restore
│
├── evidence/
│   ├── 01-lan/
│   │   ├── collect-network-info.sh   # Run on each Mac
│   │   ├── ping-matrix.sh           # Ping connectivity test
│   │   └── mac1-network-info.txt    # Mac 1 network details
│   │
│   └── 02-dns/
│       └── failure-demos.sh         # Two failure scenario scripts
│
└── ARCHITECTURE.md             # ← You are here
```
