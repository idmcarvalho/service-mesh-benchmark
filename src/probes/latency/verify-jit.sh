#!/bin/bash

# eBPF JIT Compilation Status Verification Script
# This script checks if eBPF JIT compilation is properly configured
# for optimal performance in the Service Mesh Benchmark project

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║      eBPF JIT Compilation Status Verification           ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

ISSUES_FOUND=0
WARNINGS_FOUND=0

# Check JIT enable status
echo -e "${BLUE}[1/6] Checking JIT Enable Status${NC}"
if [ -f /proc/sys/net/core/bpf_jit_enable ]; then
    JIT_ENABLE=$(cat /proc/sys/net/core/bpf_jit_enable)
    case $JIT_ENABLE in
        0)
            echo -e "      ${RED}✗ JIT Status: DISABLED (interpreter only)${NC}"
            echo -e "        ${YELLOW}CRITICAL: This will cause 10-100x performance degradation!${NC}"
            echo -e "        ${YELLOW}Fix: sudo sysctl -w net.core.bpf_jit_enable=1${NC}"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
            ;;
        1)
            echo -e "      ${GREEN}✓ JIT Status: ENABLED${NC}"
            ;;
        2)
            echo -e "      ${GREEN}✓ JIT Status: ENABLED with debug output${NC}"
            echo -e "        ${BLUE}ℹ️  Debug mode may have slight performance impact${NC}"
            ;;
        *)
            echo -e "      ${YELLOW}⚠ Unknown JIT status: $JIT_ENABLE${NC}"
            WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
            ;;
    esac
else
    echo -e "      ${RED}✗ Cannot read JIT status (/proc/sys/net/core/bpf_jit_enable not found)${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# Check JIT hardening
echo -e "${BLUE}[2/6] Checking JIT Hardening${NC}"
if [ -f /proc/sys/net/core/bpf_jit_harden ]; then
    JIT_HARDEN=$(cat /proc/sys/net/core/bpf_jit_harden)
    case $JIT_HARDEN in
        0)
            echo -e "      ${GREEN}✓ JIT Hardening: DISABLED (best performance)${NC}"
            ;;
        1)
            echo -e "      ${YELLOW}⚠ JIT Hardening: ENABLED for unprivileged (slight overhead)${NC}"
            echo -e "        ${BLUE}For best performance: sudo sysctl -w net.core.bpf_jit_harden=0${NC}"
            WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
            ;;
        2)
            echo -e "      ${YELLOW}⚠ JIT Hardening: ENABLED for all (higher overhead)${NC}"
            echo -e "        ${BLUE}For best performance: sudo sysctl -w net.core.bpf_jit_harden=0${NC}"
            WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
            ;;
    esac
else
    echo -e "      ${YELLOW}⚠ Cannot read JIT hardening status${NC}"
fi
echo ""

# Check JIT memory limit
echo -e "${BLUE}[3/6] Checking JIT Memory Limit${NC}"
if [ -f /proc/sys/net/core/bpf_jit_limit ]; then
    JIT_LIMIT=$(cat /proc/sys/net/core/bpf_jit_limit)
    JIT_LIMIT_MB=$((JIT_LIMIT / 1024 / 1024))
    if [ $JIT_LIMIT_MB -lt 256 ]; then
        echo -e "      ${YELLOW}⚠ JIT Memory Limit: ${JIT_LIMIT_MB} MB (may be low for many programs)${NC}"
        echo -e "        ${BLUE}Consider increasing: sudo sysctl -w net.core.bpf_jit_limit=524288000${NC}"
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
    else
        echo -e "      ${GREEN}✓ JIT Memory Limit: ${JIT_LIMIT_MB} MB${NC}"
    fi
else
    echo -e "      ${YELLOW}⚠ Cannot read JIT memory limit${NC}"
fi
echo ""

# Check for JIT symbols
echo -e "${BLUE}[4/6] Checking JIT Symbols (kallsyms)${NC}"
if [ -f /proc/sys/net/core/bpf_jit_kallsyms ]; then
    JIT_KALLSYMS=$(cat /proc/sys/net/core/bpf_jit_kallsyms)
    if [ "$JIT_KALLSYMS" = "1" ]; then
        echo -e "      ${GREEN}✓ JIT Symbols: ENABLED (helpful for debugging/profiling)${NC}"
    else
        echo -e "      ${BLUE}ℹ️  JIT Symbols: DISABLED${NC}"
        echo -e "        ${BLUE}Optional: sudo sysctl -w net.core.bpf_jit_kallsyms=1${NC}"
    fi
else
    echo -e "      ${YELLOW}⚠ Cannot read JIT symbols status${NC}"
fi
echo ""

# Check kernel version
echo -e "${BLUE}[5/6] Checking Kernel Version${NC}"
KERNEL_VERSION=$(uname -r)
KERNEL_MAJOR=$(echo $KERNEL_VERSION | cut -d. -f1)
KERNEL_MINOR=$(echo $KERNEL_VERSION | cut -d. -f2)

echo -e "      Kernel: ${KERNEL_VERSION}"

if [ "$KERNEL_MAJOR" -gt 5 ] || ([ "$KERNEL_MAJOR" -eq 5 ] && [ "$KERNEL_MINOR" -ge 10 ]); then
    echo -e "      ${GREEN}✓ Kernel version supports BTF/CO-RE (>= 5.10)${NC}"
else
    echo -e "      ${RED}✗ Kernel version too old (< 5.10)${NC}"
    echo -e "        ${YELLOW}Upgrade to Linux 5.10+ for BTF/CO-RE support${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# Check BTF support
echo -e "${BLUE}[6/6] Checking BTF Support${NC}"
if [ -f /sys/kernel/btf/vmlinux ]; then
    echo -e "      ${GREEN}✓ BTF available at /sys/kernel/btf/vmlinux${NC}"

    # Check BTF size
    BTF_SIZE=$(stat -c%s /sys/kernel/btf/vmlinux 2>/dev/null || echo 0)
    BTF_SIZE_MB=$((BTF_SIZE / 1024 / 1024))
    if [ $BTF_SIZE -gt 0 ]; then
        echo -e "      ${GREEN}✓ BTF size: ${BTF_SIZE_MB} MB${NC}"
    else
        echo -e "      ${YELLOW}⚠ BTF file exists but size is 0${NC}"
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
    fi
else
    echo -e "      ${RED}✗ BTF not found (required for CO-RE)${NC}"
    echo -e "        ${YELLOW}Rebuild kernel with CONFIG_DEBUG_INFO_BTF=y${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# Summary
echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                       Summary                             ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ $ISSUES_FOUND -eq 0 ] && [ $WARNINGS_FOUND -eq 0 ]; then
    echo -e "${GREEN}✅ Perfect! eBPF JIT is optimally configured for maximum performance.${NC}"
    echo ""
    exit 0
elif [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${YELLOW}⚠️  Configuration is functional but has $WARNINGS_FOUND warning(s).${NC}"
    echo -e "${YELLOW}   Your eBPF programs will work but may not achieve optimal performance.${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}❌ Found $ISSUES_FOUND critical issue(s) and $WARNINGS_FOUND warning(s).${NC}"
    echo -e "${RED}   Your eBPF programs may not work or will have severely degraded performance.${NC}"
    echo ""

    # Provide quick fix commands
    echo -e "${BLUE}Quick Fix Commands:${NC}"
    echo ""

    if [ ! -f /proc/sys/net/core/bpf_jit_enable ] || [ "$(cat /proc/sys/net/core/bpf_jit_enable)" = "0" ]; then
        echo -e "${YELLOW}# Enable JIT (CRITICAL)${NC}"
        echo -e "sudo sysctl -w net.core.bpf_jit_enable=1"
        echo ""
    fi

    if [ -f /proc/sys/net/core/bpf_jit_harden ] && [ "$(cat /proc/sys/net/core/bpf_jit_harden)" != "0" ]; then
        echo -e "${YELLOW}# Disable JIT hardening for best performance${NC}"
        echo -e "sudo sysctl -w net.core.bpf_jit_harden=0"
        echo ""
    fi

    echo -e "${YELLOW}# Make changes persistent${NC}"
    echo -e "cat <<EOF | sudo tee -a /etc/sysctl.conf"
    echo -e "net.core.bpf_jit_enable = 1"
    echo -e "net.core.bpf_jit_harden = 0"
    echo -e "net.core.bpf_jit_kallsyms = 1"
    echo -e "EOF"
    echo -e "sudo sysctl -p"
    echo ""

    exit 1
fi
