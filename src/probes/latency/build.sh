#!/bin/bash
set -e

echo "🔨 Building eBPF Latency Probe..."
echo

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check prerequisites
echo "${BLUE}📋 Checking prerequisites...${NC}"

if ! command -v rustc &> /dev/null; then
    echo "${RED}❌ Rust not found. Install with: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh${NC}"
    exit 1
fi

if ! command -v bpf-linker &> /dev/null; then
    echo "${RED}❌ bpf-linker not found. Install with: cargo install bpf-linker --no-default-features --features llvm-19${NC}"
    exit 1
fi

if ! llvm-config-19 --version &> /dev/null; then
    echo "${RED}❌ LLVM 19 not found. See README.md for installation instructions${NC}"
    exit 1
fi

echo "${GREEN}✓ All prerequisites found${NC}"
echo

# Build eBPF program
echo "${BLUE}🏗️  Building eBPF kernel program...${NC}"
cd latency-probe-ebpf

if cargo build --release --target=bpfel-unknown-none; then
    echo "${GREEN}✓ eBPF program built successfully${NC}"
    echo "   Output: target/bpfel-unknown-none/release/latency-probe"
else
    echo "${RED}❌ eBPF build failed${NC}"
    exit 1
fi

cd ..
echo

# Build userspace program
echo "${BLUE}🏗️  Building userspace loader...${NC}"
cd latency-probe-userspace

if cargo build --release; then
    echo "${GREEN}✓ Userspace program built successfully${NC}"
    echo "   Output: target/release/latency-probe"
else
    echo "${RED}❌ Userspace build failed${NC}"
    exit 1
fi

cd ..
echo

# Set capabilities (optional, requires sudo)
if [ "$EUID" -eq 0 ]; then
    echo "${BLUE}🔐 Setting capabilities...${NC}"
    setcap cap_bpf,cap_net_admin=ep latency-probe-userspace/target/release/latency-probe
    echo "${GREEN}✓ Capabilities set (can run without sudo)${NC}"
else
    echo "${BLUE}ℹ️  Run with sudo to set capabilities: sudo ./build.sh${NC}"
fi

echo
echo "${GREEN}✅ Build complete!${NC}"
echo
echo "Usage:"
echo "  sudo ./latency-probe-userspace/target/release/latency-probe"
echo "  sudo ./latency-probe-userspace/target/release/latency-probe --help"
echo
