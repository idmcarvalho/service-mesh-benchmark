#!/bin/bash
# Service Mesh Benchmark with eBPF Kernel Probes
#
# Runs the 4-way benchmark while collecting kernel-level metrics via
# eBPF probes (kprobes, tracepoints, XDP) on both worker nodes.
#
# Prerequisites:
#   - eBPF probe deployed to worker nodes via deploy-to-node.sh
#   - Workload manifests applied (baseline, cilium-ebpf, cilium-l7, istio-sidecar, istio-ambient)

set -eo pipefail

export KUBECONFIG=~/.kube/config.oci.tunnel
kubectl() { command kubectl --insecure-skip-tls-verify "$@"; }
RESULTS_DIR="./benchmarks/results"
EBPF_RESULTS_DIR="$RESULTS_DIR/ebpf"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/oci_benchmark_key}"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
PROBE_PATH="/opt/ebpf-probe/target/release/latency-probe"
PROBE_OBJECT="/opt/ebpf-probe/target/bpfel-unknown-none/release/latency-probe"

# Configuration
DURATION=30
QPS=0
CONCURRENCY_LEVELS=(10 50 100)
TRIALS=5
EBPF_SAMPLE_RATE=10  # Sample 1 in 10 context switches to reduce overhead

mkdir -p "$RESULTS_DIR" "$EBPF_RESULTS_DIR"

# Detect worker node IPs
SERVER_NODE_IP=$(kubectl get node worker-1 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
CLIENT_NODE_IP=$(kubectl get node worker-2 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
# Master IP for SSH jump (public) — set via env var
MASTER_IP="${MASTER_IP:?Set MASTER_IP env var to the master node public IP}"

echo "================================================================"
echo "Service Mesh Benchmark with eBPF Kernel Probes"
echo "================================================================"
echo "Server node: worker-1 ($SERVER_NODE_IP)"
echo "Client node: worker-2 ($CLIENT_NODE_IP)"
echo "eBPF probes: kprobes (TCP latency), tracepoints (sched_switch, kfree_skb), XDP"
echo "Trials: $TRIALS | Duration: ${DURATION}s | Concurrency: ${CONCURRENCY_LEVELS[*]}"
echo "================================================================"
date
echo ""

ssh_node() {
    local IP=$1
    shift
    ssh -i "$SSH_KEY" $SSH_OPTS -J "ubuntu@$MASTER_IP" "ubuntu@$IP" "$@"
}

# 5 scenarios
SCENARIO_NAMES=(baseline cilium-ebpf cilium-l7 istio-sidecar istio-ambient)
SCENARIO_NAMESPACES=(baseline-http cilium-ebpf cilium-l7 http-benchmark istio-ambient)
SCENARIO_URLS=(
    "http://http-server:8080/"
    "http://http-server:8080/"
    "http://http-server:8080/"
    "http://http-server:8080/"
    "http://http-server:8080/"
)

# ================================================================
# Check eBPF probe availability on both nodes
# ================================================================
echo "STEP 0: Verify eBPF probes on worker nodes"
echo "----------------------------------------------------------------"

check_probe() {
    local NODE_NAME=$1
    local NODE_IP=$2
    if ssh_node "$NODE_IP" "test -x $PROBE_PATH" 2>/dev/null; then
        echo "  OK $NODE_NAME: probe binary found"
    else
        echo "  FATAL: probe not found on $NODE_NAME ($NODE_IP)"
        echo "  Run: ./src/probes/latency/deploy-to-node.sh $MASTER_IP"
        exit 1
    fi
}

check_probe "worker-1 (server)" "$SERVER_NODE_IP"
check_probe "worker-2 (client)" "$CLIENT_NODE_IP"

# Detect network interface on server node
NET_IFACE=$(ssh_node "$SERVER_NODE_IP" "ip -o link show | grep -v lo | head -1 | awk -F: '{print \$2}' | tr -d ' '" 2>/dev/null)
echo "  Network interface on server: $NET_IFACE"
echo ""

# ================================================================
# Node labeling
# ================================================================
echo "STEP 1: Label worker nodes"
echo "----------------------------------------------------------------"
kubectl label node worker-1 benchmark-role=server --overwrite
kubectl label node worker-2 benchmark-role=client --overwrite
echo "  worker-1=server, worker-2=client"
echo ""

# ================================================================
# Deploy fortio clients
# ================================================================
echo "STEP 2: Deploy fortio clients"
echo "----------------------------------------------------------------"
for i in "${!SCENARIO_NAMES[@]}"; do
    NS="${SCENARIO_NAMESPACES[$i]}"
    POD_NAME="fortio-client"
    kubectl delete pod "$POD_NAME" -n "$NS" --ignore-not-found --wait=false 2>/dev/null || true
done
sleep 3

for i in "${!SCENARIO_NAMES[@]}"; do
    NS="${SCENARIO_NAMESPACES[$i]}"
    echo "  Deploying to $NS..."
    kubectl run fortio-client \
        --image=fortio/fortio:latest \
        --restart=Never \
        -n "$NS" \
        --labels="app=fortio-client" \
        --overrides='{"spec":{"nodeSelector":{"benchmark-role":"client"}}}' \
        -- server
done

echo "  Waiting for all fortio-clients to be ready..."
for i in "${!SCENARIO_NAMES[@]}"; do
    kubectl wait --for=condition=Ready pod/fortio-client -n "${SCENARIO_NAMESPACES[$i]}" --timeout=120s
done
echo "  All fortio-clients ready"
echo ""

# ================================================================
# Validate placement
# ================================================================
echo "STEP 3: Validate pod placement"
echo "----------------------------------------------------------------"
PLACEMENT_OK=1
for i in "${!SCENARIO_NAMES[@]}"; do
    NS="${SCENARIO_NAMESPACES[$i]}"
    NAME="${SCENARIO_NAMES[$i]}"
    CLIENT_ACTUAL=$(kubectl get pod fortio-client -n "$NS" -o jsonpath='{.spec.nodeName}' 2>/dev/null)
    SERVER_ACTUAL=$(kubectl get pod -n "$NS" -l app=http-server -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)
    if [ "$CLIENT_ACTUAL" = "$SERVER_ACTUAL" ]; then
        echo "  FATAL: $NAME - client and server co-located on $CLIENT_ACTUAL"
        PLACEMENT_OK=0
    else
        echo "  OK $NAME: client=$CLIENT_ACTUAL server=$SERVER_ACTUAL"
    fi
done
if [ "$PLACEMENT_OK" -eq 0 ]; then
    echo "FATAL: Placement validation failed"
    exit 1
fi
echo ""

# ================================================================
# Helper: start/stop eBPF probes on server node
# ================================================================
start_ebpf_probe() {
    local SCENARIO=$1
    local PROBE_DURATION=$2
    local OUTPUT_FILE="/tmp/ebpf_${SCENARIO}.json"

    echo "  Starting eBPF probe for $SCENARIO (${PROBE_DURATION}s)..."
    # Run probe in background on server node
    # Attach XDP to the primary interface, sample context switches
    ssh_node "$SERVER_NODE_IP" "sudo $PROBE_PATH \
        --ebpf-object $PROBE_OBJECT \
        --duration $PROBE_DURATION \
        --sample-rate $EBPF_SAMPLE_RATE \
        --output $OUTPUT_FILE \
        --format json \
        --progress-interval 30 \
        > /tmp/ebpf_${SCENARIO}.log 2>&1 &"

    # Also start on client node (without XDP to avoid conflict)
    local CLIENT_OUTPUT="/tmp/ebpf_${SCENARIO}_client.json"
    ssh_node "$CLIENT_NODE_IP" "sudo $PROBE_PATH \
        --ebpf-object $PROBE_OBJECT \
        --duration $PROBE_DURATION \
        --sample-rate $EBPF_SAMPLE_RATE \
        --output $CLIENT_OUTPUT \
        --format json \
        --progress-interval 30 \
        > /tmp/ebpf_${SCENARIO}_client.log 2>&1 &"
}

stop_and_collect_ebpf() {
    local SCENARIO=$1

    echo "  Waiting for eBPF probes to finish for $SCENARIO..."
    # Wait for the probe to finish (it has a duration timeout)
    sleep 5

    # Collect results from server node
    scp -i "$SSH_KEY" $SSH_OPTS -o ProxyJump="ubuntu@$MASTER_IP" \
        "ubuntu@$SERVER_NODE_IP:/tmp/ebpf_${SCENARIO}.json" \
        "$EBPF_RESULTS_DIR/ebpf_${SCENARIO}_server.json" 2>/dev/null || {
        echo "  WARNING: Could not collect eBPF results from server for $SCENARIO"
    }

    # Collect results from client node
    scp -i "$SSH_KEY" $SSH_OPTS -o ProxyJump="ubuntu@$MASTER_IP" \
        "ubuntu@$CLIENT_NODE_IP:/tmp/ebpf_${SCENARIO}_client.json" \
        "$EBPF_RESULTS_DIR/ebpf_${SCENARIO}_client.json" 2>/dev/null || {
        echo "  WARNING: Could not collect eBPF results from client for $SCENARIO"
    }

    echo "  OK eBPF data collected for $SCENARIO"
}

# ================================================================
# Run benchmarks per scenario
# ================================================================
TOTAL_RUNS=$(( ${#SCENARIO_NAMES[@]} * ${#CONCURRENCY_LEVELS[@]} * TRIALS ))
echo "STEP 4: Run benchmarks ($TOTAL_RUNS runs + eBPF probes per scenario)"
echo "================================================================"

for i in "${!SCENARIO_NAMES[@]}"; do
    SCENARIO="${SCENARIO_NAMES[$i]}"
    NAMESPACE="${SCENARIO_NAMESPACES[$i]}"
    TARGET_URL="${SCENARIO_URLS[$i]}"

    echo ""
    echo ">>> ${SCENARIO^^} namespace=$NAMESPACE"

    # Calculate total time for this scenario's benchmarks
    # warmup(10s + 5s) + trials * concurrency_levels * (duration + sleep)
    SCENARIO_TIME=$(( 15 + ${#CONCURRENCY_LEVELS[@]} * TRIALS * (DURATION + 5) + 10 ))

    # Start eBPF probe for the entire scenario duration
    start_ebpf_probe "$SCENARIO" "$SCENARIO_TIME"

    # Warmup
    echo "  Warmup: $SCENARIO @ 100c for 10s (discarded)..."
    kubectl exec fortio-client -n "$NAMESPACE" -- \
        fortio load -c 100 -qps 0 -t 10s "$TARGET_URL" > /dev/null 2>&1
    sleep 5

    # Run trials
    for C in "${CONCURRENCY_LEVELS[@]}"; do
        for T in $(seq 1 $TRIALS); do
            OUTPUT_FILE="$RESULTS_DIR/bench_${SCENARIO}_${C}c_run${T}.json"
            echo "  Running: $SCENARIO @ ${C}c trial ${T}/${TRIALS}"
            kubectl exec fortio-client -n "$NAMESPACE" -- \
                fortio load \
                -c "$C" \
                -qps "$QPS" \
                -t "${DURATION}s" \
                -json - \
                "$TARGET_URL" \
                > "$OUTPUT_FILE" \
                2> "$RESULTS_DIR/bench_${SCENARIO}_${C}c_run${T}_stderr.log"
            sleep 5
        done
    done

    # Collect resource metrics
    kubectl top pods -n "$NAMESPACE" --no-headers > "$RESULTS_DIR/${SCENARIO}_resources.txt" 2>&1 || true

    # Collect eBPF data
    stop_and_collect_ebpf "$SCENARIO"
done

# ================================================================
# Infrastructure metrics
# ================================================================
echo ""
echo "STEP 5: Collect infrastructure metrics"
echo "----------------------------------------------------------------"

# Cilium metrics
CILIUM_POD=$(kubectl get pod -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$CILIUM_POD" ]; then
    kubectl exec -n kube-system "$CILIUM_POD" -- cilium metrics list > "$RESULTS_DIR/ebpf_statistics.txt" 2>&1 || true
fi

# Istio stats
ISTIO_POD=$(kubectl get pod -n http-benchmark -l app=http-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$ISTIO_POD" ]; then
    kubectl exec -n http-benchmark "$ISTIO_POD" -c istio-proxy -- \
        curl -s localhost:15000/stats/prometheus 2>/dev/null \
        | grep -E "istio_requests_total|istio_request_duration" \
        > "$RESULTS_DIR/istio_sidecar_stats.txt" || true
fi

kubectl top nodes > "$RESULTS_DIR/cluster_nodes.txt" 2>&1 || true
kubectl get pods --all-namespaces -o wide > "$RESULTS_DIR/cluster_pods.txt" 2>&1
echo "  OK infrastructure metrics collected"

# ================================================================
# Cleanup
# ================================================================
echo ""
echo "STEP 6: Cleanup"
echo "----------------------------------------------------------------"
for i in "${!SCENARIO_NAMES[@]}"; do
    kubectl delete pod fortio-client -n "${SCENARIO_NAMESPACES[$i]}" --ignore-not-found || true
done

# ================================================================
# Summary
# ================================================================
echo ""
echo "================================================================"
echo "Benchmark Complete!"
echo "================================================================"
date
echo ""

EXPECTED=$(( ${#SCENARIO_NAMES[@]} * ${#CONCURRENCY_LEVELS[@]} * TRIALS ))
ACTUAL=$(ls "$RESULTS_DIR"/bench_*.json 2>/dev/null | wc -l)
EBPF_FILES=$(ls "$EBPF_RESULTS_DIR"/ebpf_*.json 2>/dev/null | wc -l)

echo "Fortio results: $ACTUAL / $EXPECTED expected"
echo "eBPF results:   $EBPF_FILES files in $EBPF_RESULTS_DIR/"
echo ""
ls -lh "$EBPF_RESULTS_DIR"/ 2>/dev/null

if [ "$ACTUAL" -eq "$EXPECTED" ]; then
    echo ""
    echo "SUCCESS: All benchmark files produced."
else
    echo ""
    echo "WARNING: Expected $EXPECTED fortio files but got $ACTUAL."
fi
