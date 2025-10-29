# eBPF Development Environment Setup Guide

Complete guide for setting up the eBPF development environment for the service mesh benchmark project.

## 📋 Overview

This guide will help you install and configure:
1. Rust toolchain (nightly)
2. LLVM 19 with development libraries
3. bpf-linker
4. Linux kernel headers
5. Verification tools

## 🖥️ System Requirements

### Minimum Requirements
- **OS**: Linux (Ubuntu 20.04+, Fedora 35+, Arch, or similar)
- **Kernel**: 5.10 or newer
- **Architecture**: x86_64 or ARM64
- **RAM**: 4GB minimum, 8GB recommended
- **Disk Space**: 5GB for LLVM and Rust tools

### Check Your System
```bash
# Check kernel version
uname -r  # Should be >= 5.10

# Check architecture
uname -m  # Should be x86_64 or aarch64

# Check if BTF is enabled
ls /sys/kernel/btf/vmlinux  # Should exist

# Check available disk space
df -h /usr /home  # Should have 5GB+ free
```

## 🦀 Step 1: Install Rust

### Install Rust via rustup
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

Choose option `1` (default installation).

### Configure Shell
```bash
source "$HOME/.cargo/env"

# Add to ~/.bashrc or ~/.zshrc for persistence
echo 'source "$HOME/.cargo/env"' >> ~/.bashrc
```

### Set Nightly Toolchain
```bash
rustup default nightly
rustup component add rust-src
```

### Verify Installation
```bash
rustc --version
# Should output: rustc 1.92.0-nightly (...)

cargo --version
# Should output: cargo 1.92.0-nightly (...)
```

## 🔧 Step 2: Install LLVM 19

### Ubuntu 22.04 / 24.04

```bash
# Download and run LLVM installation script
wget https://apt.llvm.org/llvm.sh
chmod +x llvm.sh
sudo ./llvm.sh 19

# Install development packages
sudo apt-get update
sudo apt-get install -y \
    llvm-19 \
    llvm-19-dev \
    llvm-19-runtime \
    libclang-19-dev \
    clang-19 \
    libpolly-19-dev

# Create symlinks (optional but recommended)
sudo update-alternatives --install /usr/bin/llvm-config llvm-config /usr/bin/llvm-config-19 100
sudo update-alternatives --install /usr/bin/clang clang /usr/bin/clang-19 100
```

### Ubuntu 20.04

```bash
# Add LLVM repository
wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | sudo apt-key add -
sudo add-apt-repository "deb http://apt.llvm.org/focal/ llvm-toolchain-focal-19 main"

# Install packages
sudo apt-get update
sudo apt-get install -y \
    llvm-19 \
    llvm-19-dev \
    libclang-19-dev \
    clang-19
```

### Fedora 38+

```bash
sudo dnf install -y \
    llvm19 \
    llvm19-devel \
    llvm19-static \
    clang19 \
    clang19-devel

# Create symlinks
sudo ln -sf /usr/bin/llvm-config-19 /usr/bin/llvm-config
sudo ln -sf /usr/bin/clang-19 /usr/bin/clang
```

### Arch Linux

```bash
# LLVM 19 is usually in the repositories
sudo pacman -S llvm clang

# Verify version
llvm-config --version  # Should be >= 19
```

### From Source (Any Distribution)

If your distribution doesn't have LLVM 19 packages:

```bash
# Download and extract LLVM 19
cd /tmp
wget https://github.com/llvm/llvm-project/releases/download/llvmorg-19.1.0/llvm-project-19.1.0.src.tar.xz
tar xf llvm-project-19.1.0.src.tar.xz
cd llvm-project-19.1.0.src

# Create build directory
mkdir build
cd build

# Configure (this takes a while)
cmake -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
    -DCMAKE_INSTALL_PREFIX=/usr/local/llvm-19 \
    ../llvm

# Build (this takes 1-2 hours, use more jobs if you have RAM)
make -j$(nproc)

# Install
sudo make install

# Add to PATH
export PATH="/usr/local/llvm-19/bin:$PATH"
export LLVM_SYS_190_PREFIX=/usr/local/llvm-19

# Make permanent
echo 'export PATH="/usr/local/llvm-19/bin:$PATH"' >> ~/.bashrc
echo 'export LLVM_SYS_190_PREFIX=/usr/local/llvm-19' >> ~/.bashrc
```

### Verify LLVM Installation

```bash
llvm-config-19 --version
# Should output: 19.x.x

clang-19 --version
# Should output: clang version 19.x.x

# Check libraries
llvm-config-19 --libs
# Should output a long list of libraries
```

## 🔗 Step 3: Install bpf-linker

### Install with Cargo

```bash
# Set LLVM environment variable
export LLVM_SYS_190_PREFIX=/usr/lib/llvm-19  # Adjust path if needed

# Install bpf-linker
cargo install bpf-linker --no-default-features --features llvm-19
```

### Troubleshooting bpf-linker Installation

**Error**: `Could not find llvm-config`

```bash
# Find where llvm-config-19 is installed
which llvm-config-19

# Set environment variable
export LLVM_SYS_190_PREFIX=/usr/lib/llvm-19
# Or
export LLVM_SYS_190_PREFIX=/usr/local/llvm-19

# Retry installation
cargo install bpf-linker --no-default-features --features llvm-19 --force
```

**Error**: `linking with 'rust-lld' failed`

```bash
# Install additional LLVM components
sudo apt-get install -y llvm-19-tools lld-19

# Or use system linker
cargo install bpf-linker --no-default-features --features llvm-19 --force
```

### Verify bpf-linker

```bash
bpf-linker --version
# Should output: bpf-linker x.x.x
```

## 📦 Step 4: Install Additional Dependencies

### Linux Kernel Headers

**Ubuntu/Debian**:
```bash
sudo apt-get install -y linux-headers-$(uname -r)
```

**Fedora/RHEL**:
```bash
sudo dnf install -y kernel-devel kernel-headers
```

**Arch Linux**:
```bash
sudo pacman -S linux-headers
```

### Build Tools

**Ubuntu/Debian**:
```bash
sudo apt-get install -y \
    build-essential \
    pkg-config \
    libelf-dev \
    zlib1g-dev
```

**Fedora/RHEL**:
```bash
sudo dnf install -y \
    gcc \
    gcc-c++ \
    make \
    pkg-config \
    elfutils-libelf-devel \
    zlib-devel
```

### eBPF Tools (for debugging)

```bash
# Ubuntu/Debian
sudo apt-get install -y bpftool linux-tools-generic

# Fedora/RHEL
sudo dnf install -y bpftool

# Verify
sudo bpftool version
```

## ✅ Step 5: Verify Complete Setup

Create a test script:

```bash
cat > verify-setup.sh << 'EOF'
#!/bin/bash

echo "🔍 Verifying eBPF Development Environment..."
echo

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

check_command() {
    if command -v $1 &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1: $(command -v $1)"
        return 0
    else
        echo -e "${RED}✗${NC} $1: not found"
        return 1
    fi
}

check_file() {
    if [ -f "$1" ]; then
        echo -e "${GREEN}✓${NC} $1 exists"
        return 0
    else
        echo -e "${RED}✗${NC} $1 not found"
        return 1
    fi
}

echo "Checking Rust installation..."
check_command rustc
check_command cargo
rustc --version

echo
echo "Checking LLVM installation..."
check_command llvm-config-19 || check_command llvm-config
check_command clang-19 || check_command clang
llvm-config-19 --version 2>/dev/null || llvm-config --version

echo
echo "Checking eBPF tools..."
check_command bpf-linker

echo
echo "Checking system requirements..."
echo -n "Kernel version: "
uname -r
check_file /sys/kernel/btf/vmlinux

echo
echo "Checking kernel headers..."
check_file /lib/modules/$(uname -r)/build/include/linux/bpf.h

echo
echo "Checking build tools..."
check_command gcc
check_command make
check_command pkg-config

echo
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ All checks passed! Ready to build eBPF programs.${NC}"
else
    echo -e "${RED}❌ Some checks failed. See above for details.${NC}"
fi
EOF

chmod +x verify-setup.sh
./verify-setup.sh
```

## 🏗️ Step 6: Build the Latency Probe

```bash
cd service-mesh-benchmark/ebpf-probes/latency-probe

# Run the build script
./build.sh
```

Expected output:
```
🔨 Building eBPF Latency Probe...
📋 Checking prerequisites...
✓ All prerequisites found

🏗️  Building eBPF kernel program...
✓ eBPF program built successfully

🏗️  Building userspace loader...
✓ Userspace program built successfully

✅ Build complete!
```

## 🧪 Step 7: Test the Probe

### Quick Test

```bash
# Run for 10 seconds
sudo ./latency-probe-userspace/target/release/latency-probe \
    --duration 10 \
    --output /tmp/test-latency.json \
    --verbose

# Generate some traffic in another terminal
curl http://example.com

# Check results
cat /tmp/test-latency.json | jq '.total_events'
```

### Integration Test

```bash
# Terminal 1: Start HTTP server
python3 -m http.server 8000

# Terminal 2: Start probe
sudo ./latency-probe --duration 30 --output /tmp/latency.json --verbose

# Terminal 3: Generate load
wrk -t2 -c10 -d20s http://localhost:8000

# After completion, analyze
cat /tmp/latency.json | jq '.percentiles'
```

## 🐛 Troubleshooting

### Problem: "Permission denied" when running probe

**Solution**:
```bash
# Option 1: Run with sudo
sudo ./latency-probe

# Option 2: Set capabilities
sudo setcap cap_bpf,cap_net_admin=ep ./latency-probe-userspace/target/release/latency-probe
./latency-probe  # Now works without sudo
```

### Problem: "BTF not found"

**Solution**:
```bash
# Check if BTF is enabled in kernel
cat /boot/config-$(uname -r) | grep CONFIG_DEBUG_INFO_BTF
# Should show: CONFIG_DEBUG_INFO_BTF=y

# If not, you need to:
# 1. Upgrade kernel to 5.10+
# 2. Or recompile kernel with BTF support
```

### Problem: "Failed to attach kprobe"

**Solution**:
```bash
# Check if function exists
sudo cat /proc/kallsyms | grep tcp_sendmsg

# Check if another eBPF program is attached
sudo bpftool prog list | grep tcp_sendmsg

# Detach old programs if needed
# (bpftool will show IDs to unload)
```

### Problem: Build fails with LLVM errors

**Solution**:
```bash
# Check LLVM installation
llvm-config-19 --version

# Reinstall bpf-linker with correct LLVM
export LLVM_SYS_190_PREFIX=$(llvm-config-19 --prefix)
cargo install bpf-linker --no-default-features --features llvm-19 --force

# Clear cargo cache
cargo clean
rm -rf ~/.cargo/registry/cache
```

## 📚 Additional Resources

- [Aya Documentation](https://aya-rs.dev/)
- [Aya Book](https://aya-rs.dev/book/)
- [LLVM Download Page](https://releases.llvm.org/)
- [Linux eBPF Documentation](https://docs.kernel.org/bpf/)
- [BPF CO-RE Reference](https://nakryiko.com/posts/bpf-portability-and-co-re/)

## 🆘 Getting Help

If you encounter issues:

1. Check the troubleshooting section above
2. Review the verification script output
3. Check the project's GitHub issues
4. Join the Aya Discord server

## ✨ Quick Reference

```bash
# Complete installation (Ubuntu 22.04+)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
rustup default nightly

wget https://apt.llvm.org/llvm.sh && chmod +x llvm.sh && sudo ./llvm.sh 19
sudo apt-get install -y llvm-19 llvm-19-dev libclang-19-dev clang-19

export LLVM_SYS_190_PREFIX=/usr/lib/llvm-19
cargo install bpf-linker --no-default-features --features llvm-19

sudo apt-get install -y linux-headers-$(uname -r) build-essential pkg-config libelf-dev

# Build
cd ebpf-probes/latency-probe
./build.sh

# Run
sudo ./latency-probe-userspace/target/release/latency-probe
```

---

**Last Updated**: October 2025
**Version**: 1.0
