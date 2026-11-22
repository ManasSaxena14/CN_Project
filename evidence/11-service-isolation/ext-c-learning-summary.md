# Extension C: Service Isolation — Learning Summary

**Extension C: Backend firewall isolation with macOS pf.**
We used macOS's built-in packet filter (`pfctl`) to restrict direct TCP access to each backend port (3001 on Mac 3, 3002 on Mac 4) so that only the two nginx edges (MAC2_IP and STANDBY_EDGE_IP) can connect to it; every other source gets a silent DROP.
Instead of overwriting `/etc/pf.conf` we created a named *anchor* (`team1-backend`) — a subordinate rule table that pf evaluates at the point where the anchor is referenced — which means our rules are completely isolated from the system's existing firewall policy and can be atomically added or removed with `pfctl -a team1-backend -f <rulefile>` / `pfctl -a team1-backend -F rules`.
Before the first `apply` we snapshot the current ruleset to `/etc/pf.anchors/team1-backend.bak` so that `remove` can restore the exact original state (the rollback guarantee).
The loopback interface (`lo0`) is explicitly passed before any block rule because macOS pf skips `lo0` by default, but making it explicit ensures the backend process's own health-check connections to `127.0.0.1` are never accidentally blocked when the default interface behaviour is changed.
This architecture mirrors AWS *Security Groups* on EC2 instances: the instances (backends) only accept traffic from the *Security Group* attached to the ALB, so even if an attacker knows the backend IP and port they cannot reach it directly — the edge is the **only** entry point.
This principle is called *defence in depth*: even if the edge is compromised, an attacker on the internal network still cannot pivot to the backend from an unauthorised IP, limiting the blast radius of any breach.
