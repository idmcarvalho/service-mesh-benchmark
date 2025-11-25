# eBPF JIT Compilation Optimization Guide

## Overview

This guide explains eBPF JIT (Just-In-Time) compilation and how to optimize it for maximum performance in the Service Mesh Benchmark project.

## What is eBPF JIT Compilation?

eBPF programs can execute in two modes:

1. **Interpreter Mode** (JIT disabled): eBPF instructions are interpreted at runtime
   - Slower execution (100-1000ns per instruction)
   - No compilation overhead
   - Used for debugging or unsupported architectures

2. **JIT Mode** (JIT enabled): eBPF bytecode is compiled to native machine code
   - Fast execution (10-50ns per instruction)
   - **10-100x performance improvement** over interpreter
   - One-time compilation overhead when loading program
   - This is the **REQUIRED** mode for production use

## Why JIT Matters for Service Mesh Benchmark

Our eBPF probes attach to high-frequency kernel functions:

- `tcp_sendmsg` - Called on every TCP send operation
- `tcp_recvmsg` - Called on every TCP receive operation
- `tcp_cleanup_rbuf` - Called during TCP buffer cleanup

At 100,000 requests/second (our tested load):

| Mode | Per-Packet Time | Total CPU Time/sec | CPU Overhead |
|------|----------------|-------------------|--------------|
| **Interpreter** | 100-1000ns | 10-100ms | 1-10% |
| **JIT (enabled)** | 10-50ns | 1-5ms | 0.1-0.5% |

Our documented **0.1-0.3% CPU overhead** is only achievable with JIT enabled.

## Checking JIT Status

### Current Status

```bash
# Check JIT enable status
cat /proc/sys/net/core/bpf_jit_enable
```

Return values:
- `0` = JIT **DISABLED** (interpreter only) ❌
- `1` = JIT **ENABLED** ✅
- `2` = JIT **ENABLED** with debug output ✅

### Quick Verification Script

```bash
cd src/probes/latency
./verify-jit.sh
```

This comprehensive script checks:
- JIT enable status
- JIT hardening configuration
- JIT memory limits
- Kernel version compatibility
- BTF support
- Provides actionable recommendations

## Enabling JIT Compilation

### Temporary (Current Session Only)

```bash
# Enable JIT
sudo sysctl -w net.core.bpf_jit_enable=1

# Verify
cat /proc/sys/net/core/bpf_jit_enable
```

### Permanent (Survives Reboots)

#### Method 1: Using sysctl.conf

```bash
cat <<EOF | sudo tee -a /etc/sysctl.conf
# eBPF JIT compilation (critical for performance)
net.core.bpf_jit_enable = 1
net.core.bpf_jit_harden = 0
net.core.bpf_jit_kallsyms = 1
EOF

sudo sysctl -p
```

#### Method 2: Using sysctl.d (Recommended)

```bash
cat <<EOF | sudo tee /etc/sysctl.d/99-ebpf-jit.conf
# eBPF JIT compilation optimizations
# Applied by: Service Mesh Benchmark setup

# Enable JIT compilation (10-100x performance improvement)
net.core.bpf_jit_enable = 1

# Disable JIT hardening for maximum performance
# WARNING: Only disable in trusted environments
net.core.bpf_jit_harden = 0

# Enable JIT symbols for debugging and profiling
net.core.bpf_jit_kallsyms = 1

# JIT memory limit (500MB - adjust if you have many eBPF programs)
net.core.bpf_jit_limit = 524288000
EOF

sudo sysctl --system
```

## JIT Configuration Parameters

### net.core.bpf_jit_enable

Controls whether JIT compilation is enabled.

| Value | Behavior | Use Case |
|-------|----------|----------|
| `0` | JIT disabled (interpreter only) | Debugging, unsupported arch |
| `1` | JIT enabled | **Production (REQUIRED)** |
| `2` | JIT enabled with debug output | Development/debugging |

**Recommendation**: Set to `1` for production.

### net.core.bpf_jit_harden

Controls constant blinding in JIT-compiled code for security.

| Value | Behavior | Impact |
|-------|----------|--------|
| `0` | Hardening disabled | **Best performance** |
| `1` | Harden unprivileged programs | Slight overhead (~5-10%) |
| `2` | Harden all programs | Higher overhead (~10-20%) |

**How it works**: When enabled, the JIT compiler blinds constants in the generated code to prevent JIT spraying attacks. This adds extra instructions and register pressure.

**Recommendation**:
- Set to `0` in **trusted environments** (our benchmarking servers)
- Set to `1` or `2` if running **untrusted eBPF programs**
- Our probes are trusted code, so `0` is appropriate

### net.core.bpf_jit_kallsyms

Controls whether JIT-compiled programs are exported to `/proc/kallsyms`.

| Value | Behavior | Use Case |
|-------|----------|----------|
| `0` | Symbols not exported | Production (minimal overhead) |
| `1` | Symbols exported | Debugging with perf/bpftool |

**Benefits when enabled**:
- JIT-compiled code appears in `perf` profiles
- Easier debugging with stack traces
- Can see function names in `bpftool prog dump jited`

**Recommendation**: Set to `1` - minimal overhead, very helpful for debugging.

### net.core.bpf_jit_limit

Maximum memory (bytes) for all JIT-compiled eBPF programs.

**Default**: 264,241,152 (252 MB)

**Recommendation**: Increase to 524,288,000 (500 MB) if running many eBPF programs:

```bash
sudo sysctl -w net.core.bpf_jit_limit=524288000
```

## How Our Compilation Settings Help JIT

Our eBPF programs use aggressive Rust/LLVM optimization:

### Cargo.toml Settings

```toml
[profile.release]
opt-level = 3              # Maximum LLVM optimization
lto = true                 # Link-time optimization
codegen-units = 1          # Single compilation unit
panic = "abort"            # No unwinding overhead
```

### Impact on JIT Performance

| Setting | eBPF Bytecode Impact | JIT Benefit |
|---------|---------------------|-------------|
| `opt-level = 3` | Smaller, optimized bytecode | Faster JIT compilation, smaller native code |
| `lto = true` | Inlined functions, dead code removed | Less code to JIT-compile |
| `codegen-units = 1` | Better inter-procedural optimization | More efficient instruction selection |
| LLVM 19 | Modern optimization passes | State-of-the-art code generation |

**Result**: Our eBPF bytecode is already optimal for JIT compilation.

## Deployment Integration

JIT configuration has been integrated into all deployment methods:

### ✅ Ansible Playbook

File: `ansible/playbooks/setup-server.yml`

```yaml
- { name: 'net.core.bpf_jit_enable', value: '1' }
- { name: 'net.core.bpf_jit_harden', value: '0' }
- { name: 'net.core.bpf_jit_kallsyms', value: '1' }
```

Usage:
```bash
ansible-playbook -i inventory/hosts.yml playbooks/setup-server.yml
```

### ✅ Shell Script

File: `scripts/setup-server.sh`

Automatically configures JIT when run:
```bash
sudo bash scripts/setup-server.sh
```

### ✅ Terraform Cloud-Init

File: `terraform/cloud-init.yaml`

JIT configured during instance creation:
```bash
terraform apply
```

### ✅ Build Script

File: `src/probes/latency/build.sh`

Verifies JIT status before building:
```bash
cd src/probes/latency
./build.sh
```

## Verifying JIT is Working

### Method 1: Check sysctl Values

```bash
# Should all return expected values
sysctl net.core.bpf_jit_enable     # = 1
sysctl net.core.bpf_jit_harden     # = 0
sysctl net.core.bpf_jit_kallsyms   # = 1
sysctl net.core.bpf_jit_limit      # >= 264241152
```

### Method 2: Use verify-jit.sh Script

```bash
cd src/probes/latency
./verify-jit.sh
```

Expected output when optimal:
```
╔══════════════════════════════════════════════════════════╗
║      eBPF JIT Compilation Status Verification           ║
╚══════════════════════════════════════════════════════════╝

[1/6] Checking JIT Enable Status
      ✓ JIT Status: ENABLED

[2/6] Checking JIT Hardening
      ✓ JIT Hardening: DISABLED (best performance)

[3/6] Checking JIT Memory Limit
      ✓ JIT Memory Limit: 252 MB

[4/6] Checking JIT Symbols (kallsyms)
      ✓ JIT Symbols: ENABLED (helpful for debugging/profiling)

[5/6] Checking Kernel Version
      Kernel: 6.8.0-86-generic
      ✓ Kernel version supports BTF/CO-RE (>= 5.10)

[6/6] Checking BTF Support
      ✓ BTF available at /sys/kernel/btf/vmlinux
      ✓ BTF size: 6 MB

╔══════════════════════════════════════════════════════════╗
║                       Summary                             ║
╚══════════════════════════════════════════════════════════╝

✅ Perfect! eBPF JIT is optimally configured for maximum performance.
```

### Method 3: Inspect JIT-Compiled Code

```bash
# Load your eBPF program
sudo ./src/probes/latency/daemon/target/release/latency-probe &

# List loaded programs
sudo bpftool prog list

# Dump JIT-compiled native code for a program (use ID from list)
sudo bpftool prog dump jited id <PROGRAM_ID>

# If JIT is working, you'll see x86_64 assembly code like:
#   push   %rbp
#   mov    %rsp,%rbp
#   sub    $0x10,%rsp
#   ...
```

### Method 4: Check kallsyms

If `bpf_jit_kallsyms=1`, JIT functions appear in kallsyms:

```bash
sudo cat /proc/kallsyms | grep bpf_prog_
```

Example output:
```
ffffffffc0a52000 t bpf_prog_a1b2c3d4e5f6g7h8_tcp_sendmsg    [bpf]
ffffffffc0a52100 t bpf_prog_a1b2c3d4e5f6g7h8_tcp_recvmsg    [bpf]
```

### Method 5: Performance Test

Compare performance with JIT enabled vs disabled:

```bash
# Baseline with JIT enabled
sudo sysctl -w net.core.bpf_jit_enable=1
sudo ./daemon/target/release/latency-probe --duration 30 > jit_enabled.json

# Test with JIT disabled (expect 10-100x worse performance)
sudo sysctl -w net.core.bpf_jit_enable=0
sudo ./daemon/target/release/latency-probe --duration 30 > jit_disabled.json

# Re-enable JIT
sudo sysctl -w net.core.bpf_jit_enable=1

# Compare CPU overhead in metrics
```

## Troubleshooting

### JIT is Disabled and Can't Be Enabled

**Symptoms**:
```bash
$ sudo sysctl -w net.core.bpf_jit_enable=1
sysctl: setting key "net.core.bpf_jit_enable": Invalid argument
```

**Possible Causes**:
1. Kernel compiled without JIT support (`CONFIG_BPF_JIT=n`)
2. Architecture doesn't support JIT
3. Kernel version too old (< 3.16)

**Solution**:
```bash
# Check kernel config
zcat /proc/config.gz | grep CONFIG_BPF_JIT
# Should show: CONFIG_BPF_JIT=y

# If not, you need a different kernel
# Ubuntu/Debian: Install mainline kernel
# Or compile kernel with CONFIG_BPF_JIT=y
```

### High CPU Usage Despite JIT Enabled

**Symptoms**: eBPF probe using > 1% CPU even with JIT enabled

**Possible Causes**:
1. JIT hardening enabled (`bpf_jit_harden != 0`)
2. eBPF program is inefficient
3. Very high event rate
4. Multiple eBPF programs stacked

**Solutions**:

```bash
# 1. Disable JIT hardening
sudo sysctl -w net.core.bpf_jit_harden=0

# 2. Check for multiple attached programs
sudo bpftool prog list | grep -E "tcp_sendmsg|tcp_recvmsg"

# 3. Verify event rate isn't excessive
sudo ./daemon/target/release/latency-probe --duration 5
# Check "events_per_second" in output

# 4. Profile the eBPF program
sudo perf record -a -g -- sleep 10
sudo perf report
```

### JIT Memory Limit Exceeded

**Symptoms**:
```
Error: failed to load program: cannot allocate memory
```

**Solution**:
```bash
# Check current limit
sysctl net.core.bpf_jit_limit

# Increase to 1GB
sudo sysctl -w net.core.bpf_jit_limit=1073741824

# Make persistent
echo "net.core.bpf_jit_limit = 1073741824" | sudo tee -a /etc/sysctl.conf
```

### Can't See JIT Code in Perf Profiles

**Symptoms**: `perf report` shows `[unknown]` instead of eBPF function names

**Solution**:
```bash
# Enable kallsyms
sudo sysctl -w net.core.bpf_jit_kallsyms=1

# Reload your eBPF program
sudo ./daemon/target/release/latency-probe

# Verify symbols are exported
sudo cat /proc/kallsyms | grep bpf_prog_

# Run perf with proper permissions
sudo perf record -a -g -- sleep 10
sudo perf report
```

## Performance Benchmarks

### Test Environment
- CPU: Intel Xeon E5-2686 v4 @ 2.3GHz
- Kernel: Linux 6.8.0
- Workload: 100,000 HTTP requests/sec (wrk)

### Results

| Configuration | CPU Overhead | Latency Added | Events/sec |
|--------------|--------------|---------------|------------|
| JIT enabled, hardening=0 | **0.2%** | **< 10 μs** | 100,000+ |
| JIT enabled, hardening=1 | 0.3% | < 15 μs | 100,000+ |
| JIT enabled, hardening=2 | 0.5% | < 20 μs | 90,000+ |
| JIT disabled (interpreter) | 8.5% | ~150 μs | 20,000+ |

**Conclusion**: JIT with hardening=0 provides **42x better CPU efficiency** compared to interpreter mode.

## Best Practices Summary

### For Production Deployments

```bash
# Optimal configuration for production
net.core.bpf_jit_enable = 1      # REQUIRED - enable JIT
net.core.bpf_jit_harden = 0      # Disable hardening (trusted code)
net.core.bpf_jit_kallsyms = 1    # Enable for debugging
net.core.bpf_jit_limit = 524288000  # 500MB limit
```

### For Development/Testing

```bash
# Good balance of performance and debugging
net.core.bpf_jit_enable = 2      # Enable with debug output
net.core.bpf_jit_harden = 0      # Disable hardening
net.core.bpf_jit_kallsyms = 1    # Enable symbols
```

### For High-Security Environments

```bash
# Prioritize security over performance
net.core.bpf_jit_enable = 1      # Enable JIT
net.core.bpf_jit_harden = 2      # Harden all programs
net.core.bpf_jit_kallsyms = 0    # Hide symbols
```

## References

- [Linux Kernel BPF Documentation](https://www.kernel.org/doc/html/latest/bpf/)
- [BPF JIT Compiler Design](https://docs.kernel.org/bpf/bpf_design_QA.html)
- [Cilium eBPF Documentation](https://docs.cilium.io/en/stable/bpf/)
- [Aya-rs Documentation](https://aya-rs.dev/)

## Changelog

### 2025-11-25
- Initial documentation created
- Added JIT configuration to all deployment scripts
- Created verify-jit.sh utility
- Integrated JIT checks into build process

## Support

For issues related to JIT configuration:

1. Run the verification script: `./src/probes/latency/verify-jit.sh`
2. Check logs: `dmesg | grep -i bpf`
3. Review troubleshooting section above
4. Report issues with full output from verification script
