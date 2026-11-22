# PHASE 2 REPORT — Computer Networks Project
## Team 1 | Mac 4 (Integration Owner / Test Client / Backup DNS)

> **Status:** In progress — teammate learning summaries to be pasted into each Extension section below.  
> **Evidence index:** see `evidence/` — each numbered folder maps to one extension.

---

## 1. What Changed from Phase 1

| Aspect | Phase 1 | Phase 2 |
|--------|---------|---------|
| DNS | Single server on Mac 1 (Python fallback) | Dual DNS: Mac 1 primary + **Mac 4 backup** (Ext A) |
| DNS TTL | Unspecified (long) | **30 s** (Ext B) — fast failover, reduced stale cache |
| Edge / nginx | Single instance on Mac 2 | Mac 2 primary + **Mac 3 standby** (Ext E) |
| Backend security | No firewall; any host can hit :3001/:3002 | **pf anchor** restricts backend ports to edge IPs only (Ext C) |
| Observability | Basic curl tests | Layer-by-layer `diagnose.sh` + mock fault drill (Ext F) |
| Evidence | 01-07 folders | Extended to **08-13** (see index below) |
| DNS records target | Always `MAC2_IP` | `APP_TARGET_IP` variable — toggled during Ext E cutover |

---

## 2. Resilience Test Results (by Extension)

### Ext A — Backup DNS (Mac 4)

**What was done:**
- Installed `dnsmasq` on Mac 4.
- Ran Mac 1's `dns/start-dns.sh` unchanged — same script, same records, generated from `config.env`.
- Configured client DNS with **both servers** (Mac 1 first, Mac 4 second) using `dns/set-client-dns.sh set`.

**Failover demo result:**
- Mac 1 stopped dnsmasq → client flushed cache → `dig app.team1.test` returned `10.202.54.225` answered by **Mac 4** (`10.202.54.68`).
- Verified with: `dig app.team1.test` → `;; SERVER: 10.202.54.68#53`.

**Evidence:** `evidence/08-backup-dns/`

**macOS DNS note:**  
`scutil --dns` shows macOS lists multiple resolvers and **rotates / parallelises** queries. When Mac 1 stops responding, the OS retries on Mac 4 within the timeout window. This is not true round-robin — Mac 1 is still tried first if reachable.

**Learning summary (paste teammate's paragraph here):**
> _[To be added by Mac 1 — DNS redundancy learnings]_

---

### Ext B — Short TTL (30 s)

**What was done:**
- `DNS_TTL=30` in `config.env`; `start-dns.sh` injects this into dnsmasq `local-ttl`.
- Demonstrated cache expiry: queried `app.team1.test`, waited 30 s, then showed stale entry gone.

**Evidence:** `evidence/09-ttl/`

**Learning summary:**
> _[To be added]_

---

### Ext C — Service Isolation / Firewall (Mac 4 Backend B :3002)

**What was done:**
- Applied `firewall/backend-firewall.sh` (Mac 3's script) on Mac 4 for port 3002.
- Used `mac4-ext-c-firewall.sh apply` → delegates without editing the shared script.
- Verified: Mac 2 (`10.202.54.225`) can reach `:3002`; any other host gets silent DROP.
- Removed firewall after demo: `sudo ./mac4-ext-c-firewall.sh remove`.

**pf anchor used:** `team1-backend`  
**Rules:** allow from MAC2_IP, allow from STANDBY_EDGE_IP, block drop all others.

**Evidence:** `evidence/11-service-isolation/`

**Learning summary (paste teammate's paragraph here):**
> _[To be added — see evidence/11-service-isolation/ext-c-learning-summary.md]_

---

### Ext D — Caching (Phase 1 Carry-over, verified in Phase 2)

**Evidence:** `evidence/06-caching/`  
**Result:** ETag identical on A and B, `304 Not Modified` on conditional GET — unchanged from Phase 1.

---

### Ext E — Standby Edge / Hot Cutover (Mac 3)

**What was done:**
- Mac 3 ran `mac3-standby-edge.sh` to bring up a second nginx instance.
- Mac 1 updated `APP_TARGET_IP` → `MAC3_IP` and restarted DNS (TTL=30s, so switch propagated in ≤30 s).
- Clients now reach Mac 3's nginx (same certs, same backends).
- Cutover verified: `dig app.team1.test` returned `10.81.95.70`.

**Evidence:** `evidence/10-ha-failover/`

**Learning summary (paste teammate's paragraph here):**
> _[To be added by Mac 2 / Mac 3]_

---

### Ext F — Faculty-Injected Fault Drill (Mac 4)

**What was done:**
- Built `troubleshoot/diagnose.sh` — 5-layer check (DNS → IP → TCP → TLS → HTTP).
- Built `troubleshoot/RUNBOOK.md` — fault table with 12 injected faults, symptoms, proof commands, fixes.
- Ran mock drill: teammate secretly broke one thing → ran `diagnose.sh` → stopped at correct layer → named cause + fix.

**Drill result:**  
_[Describe which fault was injected and how quickly it was identified]_

**Evidence:** `evidence/13-troubleshooting/`

**Learning summary:**
> _[To be added]_

---

## 3. Troubleshooting Findings

**Key insight from the drill:**  
The 5-layer model maps perfectly to real failures:
- Layer 1 (DNS): 4 out of 12 fault types are DNS-layer. The most confusing one — wrong IP from DNS — passes Layer 1 "resolved" check but fails Layer 4 TLS (SNI mismatch). `diagnose.sh` catches this by comparing resolved IP to `$APP_TARGET_IP`.
- Layer 3 (TCP): The fastest to diagnose — `nc -vz` either connects in <1 s or fails. Distinguishes "nginx down" from "IP reachable but nothing listening".
- Layer 5 (HTTP 502): The most ambiguous at first glance — could be one or both backends. `diagnose.sh` does a direct HTTP check on both backend IPs to pinpoint which one is down.

**macOS-specific nuance:**  
`/usr/bin/curl` uses LibreSSL which ignores the macOS Keychain. The `~/.curlrc` with `cacert = ~/cn-ca-bundle.pem` is the correct fix — not `-k`. This was validated in Phase 1 and carried forward.

---

## 4. Evidence Index (find any item in < 30 s)

| Folder | Extension | Contents |
|--------|-----------|---------|
| `evidence/01-lan/` | LAN setup | ifconfig, ping matrix |
| `evidence/02-dns/` | Phase 1 DNS | dig proofs, failure demos |
| `evidence/03-https/` | Phase 1 HTTPS | curl -v, cert details |
| `evidence/04-load-balancing/` | Load balancing | X-Backend alternating log |
| `evidence/05-wireshark/` | Packet capture | full-flow.pcap + screenshots |
| `evidence/06-caching/` | Caching (Ext D) | ETag + 304 responses |
| `evidence/07-failures/` | Phase 1 failures | 5 failure demo text files |
| `evidence/08-backup-dns/` | **Ext A** | Failover demo output, dig SERVER= proof |
| `evidence/09-ttl/` | **Ext B** | TTL=30s demo, cache expiry timing |
| `evidence/10-ha-failover/` | **Ext E** | Edge cutover dig output, nginx logs |
| `evidence/11-service-isolation/` | **Ext C** | pf rules, blocked/allowed connection proofs |
| `evidence/12-edge-cutover/` | **Ext E** | DNS switch timing, curl before/after |
| `evidence/13-troubleshooting/` | **Ext F** | diagnose.sh output, mock drill recording |

---

## 5. Learning Summaries

> **Instructions for teammates:** Send your one-paragraph summary to Mac 4 to be pasted here.

| Extension | Owner | Summary |
|-----------|-------|---------|
| Ext A – Backup DNS | Mac 1 + Mac 4 | _[pending]_ |
| Ext B – Short TTL | Mac 1 | _[pending]_ |
| Ext C – Firewall | Mac 3 + Mac 4 | _[pending — draft in evidence/11-service-isolation/ext-c-learning-summary.md]_ |
| Ext D – Caching | Mac 3 | _[pending]_ |
| Ext E – Standby Edge | Mac 2 + Mac 3 | _[pending]_ |
| Ext F – Fault Diagnosis | Mac 4 | _[pending]_ |
