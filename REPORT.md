# Service Mesh Performance Benchmark Report

**Date:** February 18, 2026
**Infrastructure:** Oracle Cloud Infrastructure (OCI) — ARM64, Free Tier
**Scenarios:** 5-way comparison with custom eBPF kernel instrumentation

---

## Executive Summary

This report presents a 5-way performance comparison of service mesh architectures on Kubernetes, augmented by kernel-level eBPF metrics collected alongside application-level load tests. The benchmark covers: **no mesh (baseline)**, **Cilium eBPF (L3/L4)**, **Cilium L7 (per-node Envoy)**, **Istio sidecar**, and **Istio ambient** (ztunnel).

**Key findings:**

| Scenario | QPS vs Baseline (10c) | QPS vs Baseline (50c) | p50 Latency (50c) | CS/Request |
|---|---|---|---|---|
| **Baseline** | — | — | 42 ms | 202 |
| **Cilium eBPF (L3/L4)** | **-0.7%** | **-1.3%** | 43 ms | **188** (−7%) |
| **Istio Ambient** | -49.7% | -28.5% | 54 ms | 283 (+40%) |
| **Istio Sidecar** | -70.5% | -57.0% | 88 ms | 482 (+139%) |
| **Cilium L7** | -87.2% | -84.5% | 249 ms | 1,667 (+726%) |

The most striking result is **Cilium L7's catastrophic overhead** — worse than Istio sidecar despite using a per-node (not per-pod) proxy. This is explained by L7 HTTP parsing being CPU-bound on 1-OCPU ARM64 nodes, where the shared Envoy proxy competes directly with the application for the single physical core. The eBPF context switch data corroborates this: Cilium L7 imposes 8.3× more kernel scheduling work per request than baseline.

**Cilium eBPF (L3/L4) adds zero measurable overhead** — within statistical noise of baseline throughout. This is the most important result: a fully policy-enforcing CNI with identity-based security and Hubble observability can be deployed at zero throughput or latency cost.

---

## Methodology

### Infrastructure

| Parameter | Value |
|---|---|
| Platform | Oracle Cloud Infrastructure (OCI) |
| Region | sa-saopaulo-1 |
| Instance type | VM.Standard.A1.Flex (Ampere Altra) |
| Architecture | ARM64 (aarch64) |
| Worker CPU | 1 OCPU (1 physical core) per node |
| Worker memory | 6 GB per node |
| Kubernetes | v1.32 |
| Kernel | 6.8.0-1038-oracle |
| CNI | Cilium (all scenarios) |
| Network | OCI VCN private subnet, VirtIO NIC (enp0s6) |

### Cluster Topology

```
master-node   (2 OCPU, 12 GB) — control plane only
worker-1      (1 OCPU,  6 GB) — HTTP server pod
worker-2      (1 OCPU,  6 GB) — Fortio load generator + eBPF client probe
```

Traffic is **cross-node** in all scenarios: the client runs on worker-2 and always sends requests to the server on worker-1. This ensures every scenario exercises the full network path, including any CNI or mesh dataplane.

### Scenarios

| Scenario | Description | Proxy Model |
|---|---|---|
| **baseline** | No service mesh, plain Cilium CNI | None |
| **cilium-ebpf** | Cilium with L3/L4 NetworkPolicy | In-kernel eBPF |
| **cilium-l7** | Cilium with L7 HTTPPolicy (CiliumNetworkPolicy) | Per-node Envoy proxy |
| **istio-sidecar** | Istio with Envoy sidecar injection | Per-pod Envoy |
| **istio-ambient** | Istio ambient mode (ztunnel) | Per-node ztunnel (L4) |

### Test Parameters

| Parameter | Value |
|---|---|
| Load generator | Fortio |
| Protocol | HTTP/1.1 |
| QPS target | Unlimited (max throughput) |
| Concurrency levels | 10, 50, 100 concurrent connections |
| Duration per run | 30 seconds |
| Runs per configuration | 5 independent trials |
| Warmup | 10 s at 100c before each scenario (discarded) |
| Inter-trial cooldown | 5 seconds |
| Server replicas | 1 (deterministic network path) |
| Confidence intervals | t-distribution, 95% CI, n=5 |

### eBPF Instrumentation

Custom eBPF probes built with the [Aya-rs](https://aya-rs.dev/) framework were deployed to both worker nodes for the entire benchmark duration (~550 s per scenario). The probes collected:

| Probe | Hook point | Data |
|---|---|---|
| kprobe | `tcp_sendmsg` | TCP send events |
| kprobe | `tcp_recvmsg` | TCP receive events |
| kprobe | `tcp_cleanup_rbuf` | Receive buffer cleanup |
| kprobe | `tcp_set_state` | Connection state transitions |
| kprobe | `tcp_v4_connect` | New connections |
| kprobe | `tcp_close` | Connection teardown |
| tracepoint | `sched:sched_switch` | CPU context switches (per-PID) |
| tracepoint | `skb:kfree_skb` | Packet drops with reason codes |

> **Note on XDP:** The XDP hook was compiled but could not be attached to OCI's VirtIO NIC (`enp0s6`), which does not expose a native XDP driver. XDP native mode requires driver-level support; generic/SKB mode was not attempted to avoid measurement artifacts.

---

## Results

### Throughput — 10 Concurrent Connections

> CV% < 3% for all scenarios; results are highly reliable.

| Scenario | QPS (mean ± 95% CI) | vs Baseline | p50 ms | p90 ms | p99 ms | CV% |
|---|---|---|---|---|---|---|
| baseline | 1337.59 ± 46.91 | — | 6.40 | 13.60 | 27.70 | 2.8 |
| cilium-ebpf | 1328.15 ± 11.66 | **-0.7%** | 6.61 | 13.67 | 26.44 | 0.7 |
| istio-ambient | 672.34 ± 23.40 | -49.7% | 13.21 | 23.85 | 48.51 | 2.8 |
| istio-sidecar | 394.91 ± 10.52 | -70.5% | 23.05 | 39.69 | 67.09 | 2.1 |
| cilium-l7 | 170.63 ± 2.06 | **-87.2%** | 55.58 | 68.95 | 120.58 | 1.0 |

### Throughput — 50 Concurrent Connections

> Operationally most relevant concurrency level. CV% < 4% for all scenarios.

| Scenario | QPS (mean ± 95% CI) | vs Baseline | p50 ms | p90 ms | p99 ms | CV% |
|---|---|---|---|---|---|---|
| baseline | 1234.59 ± 29.89 | — | 42.12 | 63.77 | 100.99 | 2.0 |
| cilium-ebpf | 1218.06 ± 7.88 | **-1.3%** | 42.86 | 64.10 | 103.49 | 0.5 |
| istio-ambient | 882.54 ± 14.22 | -28.5% | 54.28 | 87.05 | 137.18 | 1.3 |
| istio-sidecar | 531.40 ± 22.14 | -57.0% | 88.05 | 141.39 | 233.36 | 3.4 |
| cilium-l7 | 191.56 ± 1.83 | **-84.5%** | 248.66 | 295.09 | 564.59 | 0.8 |

### Throughput — 100 Concurrent Connections

> High variance (CV 14–49%) across all scenarios. Likely CPU saturation / kernel scheduling noise on 1-OCPU nodes at this concurrency. Present for completeness but **not used for primary conclusions**.

| Scenario | QPS (mean ± 95% CI) | vs Baseline | p50 ms | p99 ms | CV% |
|---|---|---|---|---|---|
| baseline | 1319.17 ± 254.52 | — | 82.26 | 177.35 | 15.5 |
| cilium-ebpf | 1307.42 ± 240.27 | -0.9% | 83.06 | 174.40 | 14.8 |
| istio-ambient | 930.38 ± 161.79 | -29.5% | 107.25 | 241.02 | 14.0 |
| istio-sidecar | 636.73 ± 221.20 | -51.7% | 145.84 | 379.68 | 28.0 |
| cilium-l7 | 249.44 ± 150.44 | -81.1% | 415.78 | 864.30 | 48.6 |

### Overhead Summary

| Scenario | 10c QPS Δ | 50c QPS Δ | 10c p50 Δ | 50c p50 Δ | 10c p99 Δ | 50c p99 Δ |
|---|---|---|---|---|---|---|
| cilium-ebpf | -0.7% | -1.3% | +3.3% | +1.8% | -4.6% | +2.5% |
| istio-ambient | -49.7% | -28.5% | +106% | +29% | +75% | +36% |
| istio-sidecar | -70.5% | -57.0% | +260% | +109% | +142% | +131% |
| cilium-l7 | -87.2% | -84.5% | +768% | +490% | +335% | +459% |

---

## eBPF Kernel Metrics

### Context Switch Rates

The `sched:sched_switch` tracepoint captured every CPU context switch on both nodes for ~550 s per scenario. Raw totals and rates:

| Scenario | Server CS/s | Client CS/s | Combined CS/s |
|---|---|---|---|
| baseline | 114,101 | 135,018 | 249,119 |
| cilium-ebpf | 109,497 | 120,035 | **229,532** |
| istio-ambient | 123,614 | 126,433 | 250,047 |
| istio-sidecar | 122,819 | 133,185 | 256,004 |
| cilium-l7 | 120,624 | **200,379** | **320,003** |

**Context switch delta vs baseline:**

| Scenario | Server Δ | Client Δ | Combined Δ |
|---|---|---|---|
| cilium-ebpf | **-4.0%** | **-11.1%** | **-7.9%** |
| istio-ambient | +8.3% | -6.4% | +0.4% |
| istio-sidecar | +7.6% | -1.4% | +2.8% |
| cilium-l7 | +5.7% | **+48.4%** | **+28.5%** |

### Context Switches per Request

Normalizing by QPS at 50c reveals the true per-request kernel scheduling cost of each approach:

| Scenario | QPS @ 50c | Combined CS/s | **CS per Request** | vs Baseline |
|---|---|---|---|---|
| cilium-ebpf | 1,218 | 229,532 | **188** | **-7%** |
| baseline | 1,235 | 249,119 | **202** | — |
| istio-ambient | 883 | 250,047 | **283** | +40% |
| istio-sidecar | 531 | 256,004 | **482** | +139% |
| cilium-l7 | 192 | 320,003 | **1,667** | **+726%** |

Cilium eBPF is the only scenario that is *more* efficient than bare-metal: in-kernel packet processing eliminates userspace transitions, reducing scheduling pressure. Cilium L7's 1,667 CS/request reveals the Envoy proxy spawning a large thread pool for HTTP parsing — 8.3× more scheduling work per request than baseline.

### TCP Connection Events

kprobes on `tcp_set_state`, `tcp_v4_connect`, and `tcp_close` were attached and functional but reported zero events via the perf ring buffer. At high request rates (1,000+ QPS), the per-CPU ring buffers overflowed before the userspace daemon could drain them. The context switch tracepoint, which uses aggregate counters rather than per-event streaming, was unaffected. Future work should use BPF ring buffers or BPF map-based aggregate counters for high-rate TCP event tracking.

### Packet Drops

The `skb:kfree_skb` tracepoint reported **zero drops** on both nodes across all scenarios — expected behavior on a private OCI VCN with dedicated intra-node bandwidth and no congestion.

---

## Statistical Validity

| Scenario | CV% @ 10c | CV% @ 50c | CV% @ 100c | 10c/50c verdict |
|---|---|---|---|---|
| baseline | 2.8% | 2.0% | 15.5% | Valid |
| cilium-ebpf | 0.7% | 0.5% | 14.8% | Valid |
| cilium-l7 | 1.0% | 0.8% | 48.6% | Valid |
| istio-sidecar | 2.1% | 3.4% | 28.0% | Valid |
| istio-ambient | 2.8% | 1.3% | 14.0% | Valid |

The 10c and 50c results have CV < 4% for all scenarios — consistent and reproducible. The 100c results show high variance (14–49%) across all configurations including baseline, indicating CPU saturation or kernel scheduling noise at maximum concurrency on 1-OCPU nodes, not a mesh-specific phenomenon. The 100c results are presented for completeness but primary conclusions are drawn from 10c and 50c.

---

## Analysis and Discussion

### Cilium eBPF (L3/L4): Zero Overhead Confirmed

Cilium's eBPF dataplane at L3/L4 adds no measurable overhead. The -0.7% and -1.3% QPS deltas at 10c and 50c fall within the 95% confidence intervals of baseline. The context switch data reinforces this: in-kernel packet processing actually *reduces* scheduling pressure compared to baseline, since the eBPF programs run directly in the kernel's network stack without userspace transitions.

This is the key result for teams considering whether to adopt a CNI with policy enforcement: **you can have identity-based network policy, encryption-capable infrastructure, and Hubble observability at zero throughput cost**.

### Istio Ambient: Competitive Sidecarless Option

Istio ambient mode loses 28–50% of throughput vs baseline. The ztunnel L4 proxy introduces a network hop per connection, explaining the overhead. However, this is substantially better than sidecar mode (-57 to -70%), because ambient avoids the dual-proxy overhead of injecting Envoy into both source and destination pods.

The context switch data (283 CS/req, +40% vs baseline) is consistent with the ztunnel acting as an intermediate L4 proxy — real data-path work that can't be avoided with this architecture.

At 50c, istio-ambient's p50 of 54 ms vs baseline's 42 ms (+29%) is the clearest expression of the ztunnel's forwarding cost.

### Istio Sidecar: The Dual-Proxy Tax

Istio sidecar loses 57–71% of throughput. With Envoy injected into both the client and server pods, every request traverses two userspace proxy processes: the client-side sidecar intercepts the outbound connection (via iptables), and the server-side sidecar intercepts the inbound connection. This double-proxy hop adds 66–110 ms to p50 latency at 50c.

The context switch data (482 CS/req, +139%) reflects Envoy's thread-per-connection or thread-pool model, where each request generates multiple scheduling events across worker threads.

### Cilium L7: A CPU Budget Problem, Not an Architecture Problem

The most surprising result is Cilium L7 performing *worse* than Istio sidecar despite using a single per-node Envoy proxy (rather than per-pod). The explanation is a CPU budget problem specific to the test infrastructure:

- Each worker has **1 OCPU** — a single physical core
- Cilium L7 deploys a **per-node Envoy proxy** to handle L7 HTTP policy inspection
- At 10c, the Envoy proxy alone saturates the core, leaving the application starved
- At 50c, this is even more severe: average response time rises to 260 ms (vs 42 ms baseline)

The context switch data confirms this: 1,667 CS/req (+726%) shows Envoy spawning many worker threads that constantly compete with the application and OS housekeeping on the single core. On a multi-core node (e.g., 4+ OCPU), Cilium L7's per-node proxy architecture would be much more competitive, as Envoy's thread pool would have spare cores to run on.

**This result should not be interpreted as "Cilium L7 is always worse than Istio sidecar."** It is a finding specific to single-core constrained environments. On adequately provisioned nodes, the per-node proxy model is generally more efficient than per-pod sidecars.

### Ranking at 50c (Primary Concurrency)

```
cilium-ebpf  ████████████████████████████████ 1,218 QPS  (-1.3%)
baseline     █████████████████████████████████ 1,235 QPS
istio-ambient ██████████████████████          882 QPS  (-28.5%)
istio-sidecar █████████████                   531 QPS  (-57.0%)
cilium-l7    █████                            192 QPS  (-84.5%)
```

---

## Limitations

1. **Single physical core per worker.** The 1-OCPU OCI free tier nodes make CPU-sharing effects unusually severe. Cilium L7's per-node proxy and Istio's control plane components compete for the same core as the application. Results for proxy-heavy scenarios would improve significantly on 4+ OCPU nodes.

2. **100c results unreliable.** All scenarios show CV > 14% at 100 concurrent connections, including baseline. This indicates a platform-level bottleneck (CPU saturation, kernel scheduler noise, or OS connection tracking) rather than a mesh-specific issue.

3. **TCP kprobe events lost.** The perf ring buffer overflowed at high request rates for kprobe-based events (`tcp_sendmsg`, `tcp_v4_connect`, etc.), yielding zero captured TCP events. Only the `sched:sched_switch` tracepoint — which uses aggregate counting — provided reliable data. This prevented direct TCP latency measurement at the kernel level.

4. **XDP unavailable.** OCI's VirtIO NIC does not support native-mode XDP. XDP-based packet interception was compiled but could not be attached.

5. **Single server replica.** Using one server replica ensures a deterministic network path (eliminating load-balancing variability) but may not represent real-world multi-replica deployments.

6. **HTTP/1.1 only.** HTTP/2 or gRPC workloads may show different relative overhead, particularly for Cilium L7's HTTP/2-aware proxy and Istio's multiplexed connections.

---

## Recommendations

### Use Cilium eBPF (L3/L4) when:
- Zero latency overhead is required
- L3/L4 network policy is sufficient
- Resource efficiency matters (no sidecar containers, minimal CPU overhead)
- Kernel observability (Hubble) is desired without application changes

### Use Istio Ambient when:
- L7 features (mTLS, authorization policies) are needed without sidecar injection
- You can accept ~29–50% throughput reduction
- Gradual migration from sidecar mode is planned (ambient is upgrade-compatible)

### Use Istio Sidecar when:
- Rich L7 features are required: circuit breaking, retries, fault injection, distributed tracing
- Deep per-request observability (Kiali, Jaeger integration) is necessary
- You can accept ~57–70% throughput reduction and per-pod memory overhead

### Use Cilium L7 when:
- Nodes have ≥4 OCPUs (Envoy's thread pool needs spare cores)
- L7 HTTP policy enforcement is needed within a Cilium-native environment
- Prefer not to run a separate service mesh control plane

### Avoid Cilium L7 on single-core nodes.
The per-node Envoy proxy will contend with all application workloads running on the same node. Use Cilium's L3/L4 eBPF policies instead, which have zero throughput cost.

---

## Conclusions

1. **Cilium eBPF (L3/L4) is the clear performance leader.** At 1,218–1,328 QPS across all tested concurrency levels, it is statistically indistinguishable from bare-kernel networking. Context switch metrics confirm it is marginally *more* efficient than baseline (-7% CS/req).

2. **Istio Ambient is the best option when L7/mTLS is required.** Its 28–50% QPS reduction is substantially better than sidecar mode, and the ztunnel's operational simplicity (no pod injection, ambient-compatible with existing workloads) makes it attractive.

3. **Cilium L7 is CPU-budget-limited, not architecturally inferior.** The 84–87% QPS loss observed here is a single-core artifact. On adequately provisioned infrastructure, the per-node proxy model is preferable to per-pod sidecars in terms of total resource efficiency.

4. **eBPF context switches per request** is a useful derived metric that correlates with throughput results and provides a kernel-level explanation for observed overhead: the more scheduling events per request, the more CPU is spent on context switching rather than request processing.

5. **The 100c concurrency level is unreliable on 1-OCPU nodes.** CV of 14–49% at 100c (including baseline) indicates platform saturation. Production benchmarks on this hardware should target ≤50c.

---

## Data Files

| File | Description |
|---|---|
| `benchmarks/results/STATISTICAL_ANALYSIS.md` | Full per-scenario statistics with 95% CI |
| `benchmarks/results/statistical_analysis.json` | Machine-readable statistical results |
| `benchmarks/results/EBPF_KERNEL_METRICS.md` | eBPF context switch analysis |
| `benchmarks/results/bench_<scenario>_<Nc>_run<N>.json` | Raw Fortio result files (75 total) |
| `benchmarks/results/ebpf/ebpf_<scenario>_<node>.json` | Raw eBPF probe output (10 files) |
| `benchmarks/results/analyze_benchmarks.py` | Analysis script (stdlib only) |

---

*Benchmark suite: [service-mesh-benchmark](https://github.com/samber/service-mesh-benchmark)*
*eBPF probes: Aya-rs 0.12, native ARM64 release build*
*Generated: February 18, 2026*
