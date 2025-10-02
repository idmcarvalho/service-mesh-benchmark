# Custom eBPF Probes using Aya-rs

This directory contains custom eBPF programs written in Rust using the [Aya](https://github.com/aya-rs/aya) library for advanced service mesh metrics collection.

## Why Aya?

Aya is a pure-Rust eBPF library that offers several advantages:

- **Compile once, run everywhere**: No dependency on kernel headers at runtime
- **Type safety**: Full Rust type system for eBPF programs
- **No libbpf dependency**: Lightweight and fast
- **Async support**: Integration with tokio/async-std
- **Modern development**: Better debugging and tooling

## Probes Included

### 1. `latency-probe` - Network Latency Tracking

Tracks service-to-service latency at the kernel level without application modification.

**Metrics Collected**:
- Request/response round-trip time
- Per-connection latency histograms
- Service mesh overhead calculation

**Use Case**: Compare actual network latency vs service mesh reported latency

### 2. `packet-drop-probe` - Packet Drop Analysis

Monitors packet drops and identifies causes (policy, congestion, errors).

**Metrics Collected**:
- Drop location (TC, XDP, netfilter)
- Drop reason codes
- Per-service drop rates

**Use Case**: Identify network policy impact on performance

### 3. `connection-tracker` - Connection Lifecycle Monitoring

Tracks TCP connection establishment and termination.

**Metrics Collected**:
- Connection setup time (SYN -> SYN-ACK -> ACK)
- TLS handshake duration
- Connection reuse rates
- Connection pool efficiency

**Use Case**: Measure connection pooling effectiveness in service mesh

## Prerequisites

### Development Environment

```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Install bpf-linker
cargo install bpf-linker

# Install LLVM (for eBPF compilation)
sudo apt-get install llvm clang

# Add target for eBPF
rustup target add bpfel-unknown-none
```

### Runtime Requirements

- Linux kernel >= 5.10 (for CO-RE support)
- BTF enabled kernel (`/sys/kernel/btf/vmlinux` exists)
- CAP_BPF and CAP_NET_ADMIN capabilities

## Building

Each probe is a separate Rust workspace with two components:
- `<probe>-ebpf`: The eBPF program (runs in kernel)
- `<probe>-userspace`: The userspace loader and metrics exporter

```bash
cd latency-probe

# Build eBPF program
cd latency-probe-ebpf
cargo build --release --target=bpfel-unknown-none

# Build userspace program
cd ../latency-probe-userspace
cargo build --release

# Run
sudo ./target/release/latency-probe
```

## Quick Start

### 1. Build All Probes

```bash
make -C ebpf-probes build-all
```

### 2. Run Latency Probe

```bash
# In one terminal - start the probe
sudo ./ebpf-probes/latency-probe/target/release/latency-probe \
    --duration 60 \
    --output latency-metrics.json

# In another terminal - run your benchmark
cd benchmarks/scripts
bash http-load-test.sh
```

### 3. Analyze Results

```bash
# View collected metrics
cat latency-metrics.json | jq '.histogram'

# Compare with Cilium/Istio metrics
python3 analyze-latency.py \
    --ebpf-probe latency-metrics.json \
    --cilium-metrics cilium-metrics.json \
    --istio-metrics istio-metrics.json
```

## Integration with Benchmark Framework

The probes can be run alongside standard benchmarks for deep kernel-level insights:

```bash
# Run eBPF probe in background
sudo ./ebpf-probes/latency-probe/target/release/latency-probe \
    --duration 120 \
    --output results/ebpf-latency.json &
PROBE_PID=$!

# Run standard benchmark
make test-http

# Wait for probe to finish
wait $PROBE_PID

# Generate combined report
python3 generate-report.py \
    --include-ebpf-metrics results/ebpf-latency.json
```

## Probe Architecture

```
┌─────────────────────────────────────────┐
│         Userspace Program               │
│  (Aya Rust - latency-probe-userspace)  │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │  BPF Map Reader                 │   │
│  │  - Polls perf buffers           │   │
│  │  - Aggregates metrics           │   │
│  │  - Exports to JSON/Prometheus   │   │
│  └─────────────────────────────────┘   │
└──────────────┬──────────────────────────┘
               │ (BPF syscalls)
               ▼
┌─────────────────────────────────────────┐
│         Linux Kernel                    │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │  eBPF Programs                  │   │
│  │  (Aya Rust - latency-probe-ebpf)│   │
│  │                                  │   │
│  │  - kprobe: tcp_sendmsg          │   │
│  │  - kprobe: tcp_recvmsg          │   │
│  │  - tracepoint: net/net_dev_xmit │   │
│  │  - TC: ingress/egress hooks     │   │
│  └─────────────────────────────────┘   │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │  BPF Maps                       │   │
│  │  - connection_map (hash)        │   │
│  │  - latency_histogram (array)    │   │
│  │  - events (perf buffer)         │   │
│  └─────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

## Example Output

```json
{
  "timestamp": "2025-10-02T14:30:00Z",
  "duration_seconds": 60,
  "metrics": {
    "total_requests": 150000,
    "latency_histogram": {
      "0-1ms": 120000,
      "1-5ms": 25000,
      "5-10ms": 4000,
      "10-50ms": 900,
      "50-100ms": 90,
      "100ms+": 10
    },
    "percentiles": {
      "p50": 0.8,
      "p95": 3.2,
      "p99": 8.5,
      "p999": 45.2
    },
    "overhead_analysis": {
      "kernel_processing_ms": 0.12,
      "mesh_processing_ms": 0.35,
      "application_ms": 0.45,
      "total_ms": 0.92
    }
  }
}
```

## Performance Comparison

eBPF probes have minimal overhead compared to userspace monitoring:

| Monitoring Method | CPU Overhead | Latency Added | Memory |
|-------------------|--------------|---------------|---------|
| Aya eBPF Probe    | 0.1-0.3%    | < 10μs        | ~1-2MB  |
| eBPF Exporter     | 0.5-1%      | < 50μs        | ~5MB    |
| Sidecar Metrics   | 5-10%       | 100-500μs     | 50-100MB|
| APM Agent         | 3-5%        | 50-200μs      | 30-50MB |

## Advanced Features

### Custom Metrics Export

Probes can export to multiple formats:

```bash
# Prometheus format
./latency-probe --format prometheus --port 9090

# JSON streaming
./latency-probe --format json-stream --output /dev/stdout

# InfluxDB line protocol
./latency-probe --format influx --url http://influxdb:8086
```

### Filtering

Filter specific traffic for targeted analysis:

```bash
# Only track specific service
./latency-probe --filter "service=api-server"

# Only track TCP port 80
./latency-probe --filter "port=80"

# Only track specific namespace
./latency-probe --filter "namespace=production"
```

## Troubleshooting

### Probe Not Loading

```bash
# Check kernel version
uname -r  # Should be >= 5.10

# Check BTF support
ls /sys/kernel/btf/vmlinux

# Check capabilities
sudo getcap ./latency-probe
# Should show: cap_bpf,cap_net_admin=ep
```

### No Metrics Appearing

```bash
# Check BPF programs loaded
sudo bpftool prog list | grep latency

# Check BPF maps
sudo bpftool map list

# Enable debug logging
RUST_LOG=debug ./latency-probe
```

### High Overhead

```bash
# Reduce sampling rate
./latency-probe --sample-rate 100  # Sample 1 in 100 packets

# Use aggregation
./latency-probe --aggregate-interval 10s
```

## Contributing

When adding new probes:

1. Create new directory: `ebpf-probes/<probe-name>/`
2. Use the template structure from `latency-probe`
3. Document metrics collected and use cases
4. Add integration test
5. Update this README

## References

- [Aya Documentation](https://aya-rs.dev/)
- [Aya Book](https://aya-rs.dev/book/)
- [Linux eBPF Documentation](https://docs.kernel.org/bpf/)
- [BPF Type Format (BTF)](https://docs.kernel.org/bpf/btf.html)

## License

Same as parent project (MIT)
