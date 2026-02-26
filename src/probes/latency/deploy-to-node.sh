#!/bin/bash
# Deploy and build eBPF latency probe on a remote ARM64 node
# Usage: ./deploy-to-node.sh <node-ip> [ssh-key]

set -eo pipefail

NODE_IP="${1:?Usage: ./deploy-to-node.sh <node-ip> [ssh-key]}"
SSH_KEY="${2:-~/.ssh/oci_benchmark_key}"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
REMOTE_DIR="/opt/ebpf-probe"
PROBE_SRC="$(cd "$(dirname "$0")/../.." && pwd)"

echo "================================================================"
echo "eBPF Probe Deployment to $NODE_IP"
echo "================================================================"

ssh_cmd() {
    ssh -i "$SSH_KEY" $SSH_OPTS "ubuntu@$NODE_IP" "$@"
}

scp_cmd() {
    scp -i "$SSH_KEY" $SSH_OPTS "$@"
}

# Step 1: Check prerequisites on remote node
echo "Checking remote node prerequisites..."
ssh_cmd "uname -m && cat /proc/sys/net/core/bpf_jit_enable && ls /sys/kernel/btf/vmlinux 2>/dev/null && echo 'BTF: OK' || echo 'BTF: MISSING'"

# Step 2: Install Rust on remote if not present
echo "Checking Rust installation..."
ssh_cmd "which rustc 2>/dev/null || (curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain nightly && source ~/.cargo/env && rustup component add rust-src --toolchain nightly)"

# Step 3: Install build dependencies
echo "Installing build dependencies..."
ssh_cmd "sudo apt-get update -qq && sudo apt-get install -y -qq pkg-config libssl-dev build-essential linux-headers-\$(uname -r) 2>/dev/null; source ~/.cargo/env && cargo install bpf-linker 2>/dev/null || true"

# Step 4: Copy source to remote node
echo "Copying probe source to remote node..."
ssh_cmd "sudo mkdir -p $REMOTE_DIR && sudo chown ubuntu:ubuntu $REMOTE_DIR"
rsync -az --delete \
    -e "ssh -i $SSH_KEY $SSH_OPTS" \
    "$PROBE_SRC/" \
    "ubuntu@$NODE_IP:$REMOTE_DIR/" \
    --exclude target \
    --exclude .git

# Step 5: Build on remote node
echo "Building eBPF probe on remote node (ARM64 native)..."
ssh_cmd "source ~/.cargo/env && cd $REMOTE_DIR/latency/kernel && cargo +nightly build --release --target=bpfel-unknown-none -Zbuild-std=core 2>&1 | tail -5"
ssh_cmd "source ~/.cargo/env && cd $REMOTE_DIR/latency/daemon && cargo build --release 2>&1 | tail -5"

# Step 6: Verify binary
echo "Verifying build..."
ssh_cmd "file $REMOTE_DIR/target/release/latency-probe && $REMOTE_DIR/target/release/latency-probe --help 2>&1 | head -5"

echo ""
echo "================================================================"
echo "Deployment complete!"
echo "================================================================"
echo ""
echo "Run the probe on the remote node:"
echo "  ssh -i $SSH_KEY ubuntu@$NODE_IP 'sudo $REMOTE_DIR/target/release/latency-probe --duration 60 --interface enp0s6 --output /tmp/ebpf-metrics.json'"
echo ""
echo "Collect results:"
echo "  scp -i $SSH_KEY ubuntu@$NODE_IP:/tmp/ebpf-metrics.json ./benchmarks/results/"
