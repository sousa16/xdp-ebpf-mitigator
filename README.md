# xdp-ebpf-mitigator

**xdp-ebpf-mitigator** is a kernel-level packet filtering and DDoS mitigation system built in Go and C. An XDP/eBPF program attached at the NIC driver level drops malicious traffic before it ever reaches the standard Linux networking stack, while a Go control plane manages the kernel-space BPF maps that decide what gets dropped.

> **The Elevator Pitch:** A Go control plane driving an XDP/eBPF data plane for kernel-level packet filtering, built from the eBPF verifier up rather than from a framework down. Resilient anycast BGP routing and deep observability are optional extensions on top of that core.

---

## Engineering Journal

Development is documented in real time:

- **[`/docs/notes`](./docs/notes)** — Raw study notes and Go/systems patterns encountered during development.

## Key Features

**High-Speed Data Plane**
XDP-based packet filtering and DDoS mitigation runs at the NIC driver level, before the kernel networking stack is even involved. Latency overhead is measured in nanoseconds.

**State Reconciliation**
A control loop continuously monitors Linux network namespaces, veth configurations, and attached XDP programs. If state drifts — interfaces deleted, namespaces missing, eBPF programs manually detached — it detects and re-applies the desired configuration automatically.

**Resilient Routing** *(optional module — see Roadmap)*
Anycast BGP via GoBGP, integrated with BFD (Bidirectional Forwarding Detection) for sub-second link failure detection and automatic failover between regions.

**Deep Observability** *(optional module — see Roadmap)*
Custom eBPF exporters push P99 tail latency and packet processing timestamps directly from the kernel to Prometheus. No userspace sampling overhead.

---

## Architecture

A single Go daemon on each Linux node: it manages local Netlink state (namespaces, veth pairs), loads and manages the XDP/eBPF program, and pushes/removes entries in the kernel-space BPF map that the eBPF program checks on every packet.

```
┌───────────────────────────────────────────┐
│                Go Control Plane            │
│                                             │
│   Netlink Controller   eBPF Map Bridge     │
│   (namespaces, veth)   (blacklist updates) │
└───────────────┬─────────────┬──────────────┘
                │             │
                ▼             ▼
        ┌───────────────────────────┐
        │     XDP / eBPF Program     │
        │  (C, attached at NIC hook) │
        │  drops packets matching    │
        │  the kernel-space map      │
        └───────────────────────────┘
```

---

## Roadmap

Structured as a **Core Path** — the part that has to get built — and **Optional Depth Modules**, which are worth doing but aren't gating. See the full roadmap doc for the mastery-gate criteria per stage.

### Core Path

**Stage 0 — Go Foundations** ⚪
- [ ] **Netlink Controller** — Full lifecycle management of network namespaces and veth pairs using `vishvananda/netlink`. Implemented with namespace-scoped `netlink.Handle` instances to avoid thread-namespace coupling bugs. Includes idempotent reconciliation and partial-state detection.

**Stage 1 — C Fundamentals** ⚪
- [ ] Pointers, structs, and fixed-size arrays to the level needed for restricted eBPF C — no malloc, no unbounded loops.
- [ ] Checkpoint: a plain C program that parses a raw Ethernet/IP header via a struct pointer, no kernel involved.

**Stage 2 — eBPF Foundations** ⚪
- [ ] First eBPF "Hello World" and tracing program.
- [ ] Checkpoint: First XDP Skeleton — attaches, drops/passes pings on command, loaded via `cilium/ebpf`.

**Stage 3 — XDP Data Plane** ⚪
- [ ] **XDP DDoS Mitigator** — C-based eBPF program attached at the XDP hook for NIC-level packet processing. Go control plane populates eBPF maps with blacklisted IPs to drop malicious traffic before it touches the kernel networking stack. Auto-blacklists sources exceeding a PPS threshold.
- [ ] **State Drift Detection** — Auto-recovery daemon that detects and repairs state drift: deleted interfaces, missing namespaces, and manually detached XDP programs.

**Stage 4 — Kubernetes & Cilium** ⚪
- [ ] **Cilium CNI Deployment** — Deploy this project's data-plane concepts on a real `kind` or `k3s` cluster with Cilium as the CNI.
- [ ] **Network Policy Implementation** — L3, L4, and L7-aware Network Policies via Cilium, with Hubble flow visibility.
- [ ] **cilium/cilium Contributions** — Merged PRs in the upstream Cilium repository.

### Optional Depth Modules

**Module A — Resilient Routing (BGP)** ⚪
- [ ] **GoBGP Integration** — Anycast service advertising across multi-cloud nodes via a single Service IP. GoBGP embedded as a library in the agent.
- [ ] **BFD Implementation** — Sub-second link failure detection between regions, catching failures standard BGP timers miss.
- [ ] **Chaos Sidecar** — `tc/netem`-based utility to inject packet loss, latency, jitter, and PMTU discovery failures for resilience testing.
- [ ] **Route Dampening** — Flapping node detection: quarantine peers that join/leave too rapidly to prevent BGP convergence storms.

**Module B — Observability & SRE Craft** ⚪
- [ ] **eBPF Latency Tracker** — Kernel-level timestamps from NIC ingress to socket receive, exported as Prometheus histograms for P50/P99 tail latency.
- [ ] **Performance Audit** — Load test the XDP filter against standard `iptables`. Document CPU usage and throughput difference with reproducible numbers.
- [ ] **SLO-Based Alerting** — Grafana dashboard implementing the four Golden Signals with explicit SLO definitions and a drift-detection panel.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Go, C (restricted eBPF) |
| Networking | BGP (GoBGP), Anycast, BFD — Module A only |
| Kernel | XDP, eBPF Maps, Linux Namespaces, Netlink |
| Observability | Prometheus, Grafana, custom eBPF exporters — Module B only |
| Tooling | perf, bpftrace, tc/netem |

---

## Quick Start

> **Platform note:** Netlink, XDP, and eBPF are Linux kernel APIs — this needs a real Linux kernel, not macOS. `setup.sh` refuses to run anywhere else.

Any Ubuntu machine works, physical or virtual. Development currently happens on
an Ubuntu 24.04 workstation (x86_64) and an Ubuntu Server 26.04 VM (aarch64),
but nothing is pinned to a release or architecture: `setup.sh` resolves package
names against whatever apt offers and takes the Go version from `go.mod`.

The one behavioural difference is how XDP attaches. On bare metal with a
supporting NIC driver you get a driver-native attach; in a VM, `virtio-net` has
no native XDP path, so programs attach in generic/skb mode. Both are
functionally correct — skb mode is just slower. `setup.sh` detects which one
you're on and reports it.

```bash
git clone https://github.com/sousa16/xdp-ebpf-mitigator.git
cd xdp-ebpf-mitigator

# Installs the clang/LLVM + libbpf toolchain, kernel headers, bpftool and Go,
# then fetches modules and reports kernel eBPF/XDP support.
# Run as your normal user — it escalates for apt on its own and refuses sudo,
# which would otherwise put the Go module cache in /root.
./setup.sh

make build            # -> ./mitigator-ctl

# Requires root for Netlink/namespace operations
sudo ./mitigator-ctl

# Requires root
make test

make clean
```

> Netlink and XDP operations require `CAP_NET_ADMIN`. Tear down all created state with:
> `sudo ip netns del mitigator-ns && sudo ip link del veth-host`

---

## Repository Structure

```
xdp-ebpf-mitigator/
├── src/
│   └── cmd/
│       └── netlink-controller/           # Stage 0: namespace & veth lifecycle
│           ├── main.go
│           └── main_test.go
├── docs/
│   ├── notes/
│   │   ├── getting-started-with-ebpf/
│   │   │   ├── ebpf-basics.md            # eBPF fundamentals, maps, programs
│   │   │   └── ebpf-for-networking.md    # XDP, TC hooks, container networking
│   │   └── go-patterns.md                # Go patterns hit during development
│   └── images/
│       └── getting-started-with-ebpf/    # Diagrams and screenshots for the notes
├── Makefile                              # build, test, clean targets
├── setup.sh                              # Provisions an Ubuntu dev environment
├── go.mod
├── go.sum
├── .gitignore
└── LICENSE
```

The Go module is `github.com/sousa16/xdp-ebpf-mitigator`. `make build` compiles
`src/cmd/netlink-controller/` into a `mitigator-ctl` binary at the repo root,
which is gitignored.

---

## License

MIT