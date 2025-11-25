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
    echo "${RED}❌ bpf-linker not found. Install with: cargo install bpf-linker${NC}"
    exit 1
fi

# Check for LLVM (optional, bpf-linker can use bundled LLVM)
if llvm-config-19 --version &> /dev/null 2>&1; then
    echo "${GREEN}✓ LLVM 19 found${NC}"
elif llvm-config --version &> /dev/null 2>&1; then
    LLVM_VER=$(llvm-config --version)
    echo "${GREEN}✓ LLVM $LLVM_VER found${NC}"
else
    echo "${BLUE}ℹ️  System LLVM not found, using bpf-linker's bundled LLVM${NC}"
fi

echo "${GREEN}✓ All prerequisites found${NC}"
echo

# Check eBPF JIT compilation status
echo "${BLUE}🔍 Checking eBPF JIT status...${NC}"
if [ -f /proc/sys/net/core/bpf_jit_enable ]; then
    JIT_STATUS=$(cat /proc/sys/net/core/bpf_jit_enable)
    case $JIT_STATUS in
        0)
            echo "${RED}⚠️  WARNING: eBPF JIT is DISABLED!${NC}"
            echo "${RED}   This will severely impact performance (10-100x slower)${NC}"
            echo "${BLUE}   Enable with: sudo sysctl -w net.core.bpf_jit_enable=1${NC}"
            read -p "   Continue anyway? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
            ;;
        1)
            echo "${GREEN}✓ eBPF JIT is enabled${NC}"
            ;;
        2)
            echo "${GREEN}✓ eBPF JIT is enabled with debug output${NC}"
            ;;
    esac

    # Check JIT hardening
    if [ -f /proc/sys/net/core/bpf_jit_harden ]; then
        JIT_HARDEN=$(cat /proc/sys/net/core/bpf_jit_harden)
        if [ "$JIT_HARDEN" != "0" ]; then
            echo "${BLUE}ℹ️  JIT hardening is enabled (value: $JIT_HARDEN)${NC}"
            echo "${BLUE}   For best performance, disable with: sudo sysctl -w net.core.bpf_jit_harden=0${NC}"
        else
            echo "${GREEN}✓ JIT hardening is disabled (optimal for performance)${NC}"
        fi
    fi
else
    echo "${BLUE}ℹ️  Cannot check JIT status (/proc/sys/net/core/bpf_jit_enable not found)${NC}"
    echo "${BLUE}   This is normal on some systems or when not running as root${NC}"
fi
echo

# Build eBPF program
echo "${BLUE}🏗️  Building eBPF kernel program...${NC}"
cd kernel

if cargo +nightly build --release --target=bpfel-unknown-none -Zbuild-std=core; then
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
cd daemon

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
    setcap cap_bpf,cap_net_admin=ep daemon/target/release/latency-probe
    echo "${GREEN}✓ Capabilities set (can run without sudo)${NC}"
else
    echo "${BLUE}ℹ️  Run with sudo to set capabilities: sudo ./build.sh${NC}"
fi

echo
echo "${GREEN}✅ Build complete!${NC}"
echo
echo "Usage:"
echo "  sudo ./daemon/target/release/latency-probe"
echo "  sudo ./daemon/target/release/latency-probe --help"
echo
