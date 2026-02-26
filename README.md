# Service Mesh Benchmark

A benchmarking framework comparing service mesh architectures on Kubernetes, augmented with custom **eBPF kernel instrumentation** for kernel-level observability. Runs on Oracle Cloud Infrastructure Free Tier (ARM64).

## Key Results

Five-scenario comparison on OCI ARM64 (Kubernetes 1.32, Fortio load generator, 30s runs × 5 trials):

| Scenario | QPS vs Baseline (10c) | p50 Latency (50c) | Context Switches/Req |
|---|---|---|---|
| **Baseline** (no mesh) | — | 42 ms | 202 |
| **Cilium eBPF** (L3/L4) | **−0.7%** | 43 ms | 188 (−7%) |
| **Istio Ambient** (ztunnel) | −49.7% | 54 ms | 283 (+40%) |
| **Istio Sidecar** | −70.5% | 88 ms | 482 (+139%) |
| **Cilium L7** (per-node Envoy) | −87.2% | 249 ms | 1,667 (+726%) |

See [REPORT.md](REPORT.md) for the full analysis.

---

## Project Structure

```
service-mesh-benchmark/
├── src/
│   ├── api/                        # FastAPI benchmark orchestration API
│   ├── analysis/                   # Statistical and cost analysis modules
│   ├── tests/                      # 7-phase test framework
│   └── probes/                     # eBPF kernel instrumentation (Rust/Aya)
│       ├── common/                 # Shared kernel/userspace types
│       └── latency/
│           ├── kernel/             # BPF programs (kprobes, tracepoints, XDP)
│           └── daemon/             # Userspace collector and exporter
├── workloads/
│   └── kubernetes/                 # Benchmark workload manifests (Fortio)
│       ├── baseline-http-service.yaml
│       ├── http-service.yaml
│       ├── cilium-l7-http-service.yaml
│       ├── cilium-ingress-http-service.yaml
│       └── istio-ambient-http-service.yaml
├── infrastructure/
│   ├── terraform/oracle-cloud/     # OCI cluster provisioning (Terraform)
│   └── ansible/playbooks/          # Service mesh installation (Ansible)
├── benchmarks/results/             # Benchmark output (gitignored)
├── docs/                           # Architecture and implementation guides
├── frontend/                       # Svelte dashboard for result visualization
├── tools/ci/                       # GitHub Actions workflows
├── generate-report.py              # Report generation with statistical analysis
├── run-4way-benchmarks.sh          # 5-scenario Fortio benchmark runner
├── run-benchmarks-with-ebpf.sh     # Coordinated Fortio + eBPF metrics collection
├── run-comprehensive-benchmarks.sh # Full benchmark suite with cluster diagnostics
└── Makefile                        # Build and deployment automation
```

---

## Benchmark Scenarios

All scenarios use [Fortio](https://github.com/fortio/fortio) as the load generator. Server pods are pinned to `worker-1`, client pods to `worker-2` for deterministic cross-node traffic.

| Scenario | Namespace | Description |
|---|---|---|
| `baseline` | `baseline-http` | No service mesh — control group |
| `cilium-ebpf` | `cilium-ebpf` | Cilium with eBPF L3/L4 only, no proxy |
| `cilium-l7` | `cilium-l7` | Cilium with per-node Envoy via `CiliumNetworkPolicy` |
| `istio-sidecar` | `http-benchmark` | Istio with per-pod Envoy sidecar injection |
| `istio-ambient` | `istio-ambient` | Istio ambient mode (ztunnel, no sidecars) |

---

## eBPF Probe

A custom Rust/[Aya](https://github.com/aya-rs/aya) eBPF probe collects kernel-level metrics alongside Fortio tests.

**Attached probes:**
- `sched_switch` tracepoint — context switches per request (sampled)
- `tcp_v4_connect` / `tcp_close` kprobes — connection lifecycle
- `kfree_skb` tracepoint — packet drops
- XDP — packet inspection (falls back gracefully on VirtIO NICs)

**Build and deploy to a worker node:**
```bash
export MASTER_IP=<your-master-public-ip>
./src/probes/latency/deploy-to-node.sh <worker-internal-ip>
```

The script syncs source, builds natively on the ARM64 node (requires Rust nightly + `bpf-linker`), and verifies the binary.

---

## Quick Start

### Prerequisites

- Oracle Cloud Infrastructure account (Free Tier compatible)
- Terraform >= 1.5.0
- kubectl
- Ansible
- Python 3.9+ with [Poetry](https://python-poetry.org/)
- Rust nightly + `bpf-linker` (for eBPF probe builds on worker nodes)
- SSH key pair

### 1. Deploy Infrastructure

```bash
cp infrastructure/terraform/oracle-cloud/terraform.tfvars.example \
   infrastructure/terraform/oracle-cloud/terraform.tfvars
# Edit terraform.tfvars: tenancy_ocid, user_ocid, fingerprint,
#                        private_key_path, allowed_ssh_cidr
make init
make deploy-infra
```

This creates 1 master node (2 OCPU, 12 GB) and 2 worker nodes (1 OCPU, 6 GB each) on OCI ARM64.

### 2. Configure kubectl

```bash
# Tunnel the k8s API through the master node
ssh -L 16443:localhost:6443 ubuntu@<master-ip> -N &
export KUBECONFIG=~/.kube/config.oci.tunnel
```

### 3. Install Service Meshes

```bash
# Install Cilium (required for all scenarios)
ansible-playbook -i infrastructure/ansible/inventory/hosts.ini \
    infrastructure/ansible/playbooks/setup-cilium.yml

# Install Istio (for Istio scenarios)
ansible-playbook -i infrastructure/ansible/inventory/hosts.ini \
    infrastructure/ansible/playbooks/setup-istio.yml
```

### 4. Deploy Workloads

```bash
kubectl apply -f workloads/kubernetes/baseline-http-service.yaml
kubectl apply -f workloads/kubernetes/http-service.yaml
kubectl apply -f workloads/kubernetes/cilium-l7-http-service.yaml
kubectl apply -f workloads/kubernetes/cilium-ingress-http-service.yaml
kubectl apply -f workloads/kubernetes/istio-ambient-http-service.yaml
```

### 5. Run Benchmarks

```bash
export MASTER_IP=<master-public-ip>

# Fortio only (5 scenarios, 3 concurrency levels, 5 trials each)
./run-4way-benchmarks.sh

# Fortio + eBPF kernel metrics (requires deployed probes)
./run-benchmarks-with-ebpf.sh

# Full suite with cluster diagnostics
./run-comprehensive-benchmarks.sh
```

Results are written to `benchmarks/results/` (gitignored).

### 6. Generate Report

```bash
python generate-report.py
```

---

## Python API

A FastAPI application at `src/api/` orchestrates benchmark runs and exposes results:

```bash
poetry install
poetry run uvicorn src.api.main:app --reload
```

Endpoints: `/health`, `/benchmarks`, `/metrics`, `/reports`, `/ebpf`, `/kubernetes`

---

## Development

### Install dependencies

```bash
poetry install
```

### Code quality

```bash
make lint      # ruff + black check + mypy
make format    # auto-format
make test      # pytest (Phase 1 pre-deployment tests, no cluster required)
```

### Test phases

The test framework is organized into 7 phases:

| Phase | Description | Requires |
|---|---|---|
| 1 | Pre-deployment validation | Nothing |
| 2 | Infrastructure readiness | Running cluster |
| 3 | Baseline performance | No-mesh workloads |
| 4 | Service mesh tests | Installed mesh |
| 5 | Comparative analysis | All scenarios |
| 6 | Stress tests | All scenarios |

---

## Infrastructure

**Cluster topology:**
```
master-node  (2 OCPU, 12 GB) — control plane only
worker-1     (1 OCPU,  6 GB) — HTTP server pods
worker-2     (1 OCPU,  6 GB) — Fortio client pods
```

**OCI Free Tier allocation used:**
- Compute: 4 OCPUs, 24 GB RAM (Ampere A1, ARM64)
- Network: OCI VCN, private subnet, VirtIO NIC (`enp0s6`)

---

## Security

- Never commit `terraform.tfvars` or `*.pem`/`*.key` files (covered by `.gitignore`)
- `MASTER_IP` and `SSH_KEY` in benchmark scripts must be set via environment variables
- SSH access should be restricted to your IP via `allowed_ssh_cidr` in `terraform.tfvars`
- Destroy infrastructure when not in use: `make destroy`

---

## Contributing

Contributions welcome. Useful areas:

- Additional mesh implementations (Linkerd, Consul)
- Multi-region benchmark support
- BPF ring buffer migration (replaces perf buffers for TCP tracking)
- Distributed tracing integration
- Multi-cloud infrastructure (AWS, GCP)

## License

MIT License — see [LICENSE](LICENSE) for details.

## References

- [Istio Documentation](https://istio.io/docs/)
- [Cilium Documentation](https://docs.cilium.io/)
- [Aya eBPF Framework](https://aya-rs.dev/)
- [Fortio Load Testing Tool](https://github.com/fortio/fortio)
- [Oracle Cloud Free Tier](https://www.oracle.com/cloud/free/)
