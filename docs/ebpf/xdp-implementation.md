# XDP Implementation Status

## Overview

XDP (eXpress Data Path) support has been added to the eBPF latency probes for ultra-low-latency packet monitoring at the NIC driver level.

## Implementation Status

### ✅ Completed Features

1. **XDP Packet Monitor Program** - [handlers.rs:514-676](../../src/probes/latency/kernel/src/handlers.rs#L514)
   - Parses Ethernet → IPv4 → TCP/UDP headers
   - Tracks per-connection packet and byte statistics
   - Protocol-specific counters (TCP, UDP, ICMP)
   - Returns `XDP_PASS` (monitoring only, no filtering)

2. **Data Structures** - [types.rs:87-101](../../src/probes/common/src/types.rs#L87)
   - `XdpConnStats`: packet_count, byte_count, last_seen_ns, drop_count

3. **BPF Maps** - [maps.rs:57-66](../../src/probes/latency/kernel/src/maps.rs#L57)
   - `XDP_CONN_STATS`: Per-connection statistics (max 10,240 entries)

4. **Statistics Constants** - [constants.rs:177-196](../../src/probes/common/src/constants.rs#L177)
   - `STAT_XDP_PACKETS`, `STAT_XDP_IPV4_PACKETS`, `STAT_XDP_TCP_PACKETS`, etc.

5. **Userspace Loader** - [loader.rs:228-250](../../src/probes/latency/daemon/src/loader.rs#L228)
   - `attach_xdp(interface, mode)` method
   - Returns `AttachResult::Attached` or `AttachResult::NotFound`
   - Supports SKB_MODE, DRV_MODE, HW_MODE

### ❌ Not Yet Implemented

- IPv6 support (currently IPv4 only)
- Packet filtering/dropping capabilities
- Sampling for high-traffic environments
- XDP_REDIRECT for load balancing
- Prometheus metrics export
- Automated NIC capability detection

## XDP Modes

| Mode | Description | Compatibility | Flag |
|------|-------------|---------------|------|
| SKB | Generic (kernel stack) | All NICs | `XdpFlags::SKB_MODE` |
| DRV | Native (NIC driver) | XDP-capable NICs | `XdpFlags::DRV_MODE` |
| HW | Hardware offload | SmartNICs | `XdpFlags::HW_MODE` |

## Usage

### Attaching XDP

```rust
use aya::programs::XdpFlags;
use latency_probe::loader::{ProbeLoader, AttachResult};

let mut loader = ProbeLoader::load(None)?;

// Attach to network interface
match loader.attach_xdp("eth0", XdpFlags::SKB_MODE)? {
    AttachResult::Attached => println!("XDP attached successfully"),
    AttachResult::NotFound => println!("XDP program not in eBPF object (optional)"),
}
```

### Checking Attachment

```bash
# Check if XDP is attached
ip link show eth0 | grep xdp

# Expected output examples:
# xdp/id:123              (native DRV mode)
# xdpgeneric/id:123       (generic SKB mode)
# xdpoffload/id:123       (hardware HW mode)
```

### Detaching XDP

```bash
# Manual detach
ip link set dev eth0 xdp off

# Or let program exit (auto-detaches)
```

## Statistics Collected

### Global Stats (in `STATS` map)

- `STAT_XDP_PACKETS` - Total packets processed
- `STAT_XDP_IPV4_PACKETS` - IPv4 packets
- `STAT_XDP_TCP_PACKETS` - TCP packets
- `STAT_XDP_UDP_PACKETS` - UDP packets
- `STAT_XDP_ICMP_PACKETS` - ICMP packets
- `STAT_XDP_OTHER_PACKETS` - Other protocols

### Per-Connection Stats (in `XDP_CONN_STATS` map)

```rust
XdpConnStats {
    packet_count: u64,    // Packets for this 4-tuple
    byte_count: u64,      // Bytes for this 4-tuple
    last_seen_ns: u64,    // Last packet timestamp
    drop_count: u64,      // Drops (currently unused)
}
```

## Supported NIC Drivers (Native XDP)

Check driver support:
```bash
ethtool -i <interface> | grep driver
```

Common XDP-capable drivers:
- Intel: `i40e`, `ixgbe`, `igb`
- Mellanox/NVIDIA: `mlx4`, `mlx5`
- Broadcom: `bnxt_en`
- Netronome: `nfp` (also supports HW mode)
- Virtual: `virtio_net` (KVM/QEMU)

Reference: https://github.com/iovisor/bcc/blob/master/docs/kernel-versions.md#xdp

## Current Limitations

1. **IPv4 only** - No IPv6 support yet
2. **Monitoring only** - No packet filtering (always returns XDP_PASS)
3. **No sampling** - Processes every packet
4. **Fixed map size** - 10,240 connection limit

## Troubleshooting

### "Failed to attach XDP"

**Causes**:
- Insufficient permissions (need root or CAP_NET_ADMIN + CAP_BPF)
- Interface doesn't exist or is DOWN
- Another XDP program already attached
- DRV_MODE not supported by NIC driver

**Solutions**:
```bash
# Check permissions
sudo -i

# Check interface
ip link show eth0
ip link set eth0 up

# Remove conflicting XDP
ip link set dev eth0 xdp off

# Try SKB mode instead
# (in code: use XdpFlags::SKB_MODE)
```

### "xdp_packet_monitor program not found"

**Cause**: eBPF object doesn't include XDP program

**Solution**:
```bash
cd src/probes
cargo build --release --target bpfel-unknown-none

# Verify XDP section exists
llvm-objdump -h target/bpfel-unknown-none/release/latency-probe | grep xdp
```

## Next Steps

To implement the missing features, run:
```bash
# IPv6 support
# Packet filtering
# Sampling
# XDP_REDIRECT
# Prometheus integration
# NIC auto-detection
```

## References

- [Linux XDP Documentation](https://docs.kernel.org/bpf/xdp.html)
- [XDP Tutorial](https://github.com/xdp-project/xdp-tutorial)
- [Aya XDP Examples](https://github.com/aya-rs/aya/tree/main/aya/examples)
- [BCC XDP Reference](https://github.com/iovisor/bcc/blob/master/docs/kernel-versions.md#xdp)

---

**Status**: XDP implementation complete for basic packet monitoring. Performance testing needed to quantify improvements.
