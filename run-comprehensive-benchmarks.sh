#!/bin/bash
# Comprehensive Service Mesh Benchmarking
# Compares Baseline vs Istio (sidecar) vs Cilium (sidecarless/eBPF)
#
# Methodology:
#   - Server pods pinned to one worker node, client pods to another (deterministic cross-node path)
#   - 10s warmup run (discarded) before each scenario
#   - 5 independent trials per scenario for statistical validity

set -eo pipefail

export KUBECONFIG=~/.kube/config.oci
RESULTS_DIR="./benchmarks/results"
mkdir -p "$RESULTS_DIR"

DURATION=60
QPS=0
CONNECTIONS=50
TRIALS=5
ERRORS=0

echo "=================================================="
echo "Service Mesh Benchmark Suite"
echo "Scenarios: Baseline | Istio (Sidecar) | Cilium (eBPF)"
echo "Duration: ${DURATION}s | Connections: $CONNECTIONS | Trials: $TRIALS"
echo "=================================================="
date
echo ""

# ================================================================
# Node labeling for deterministic pod placement
# ================================================================
label_nodes() {
    echo "Labeling worker nodes for benchmark placement..."
    WORKERS=($(kubectl get nodes --no-headers -l '!node-role.kubernetes.io/control-plane' -o custom-columns=NAME:.metadata.name))
    if [ ${#WORKERS[@]} -lt 2 ]; then
        echo "FATAL: Need at least 2 worker nodes, found ${#WORKERS[@]}"
        exit 1
    fi
    SERVER_NODE="${WORKERS[0]}"
    CLIENT_NODE="${WORKERS[1]}"
    kubectl label node "$SERVER_NODE" benchmark-role=server --overwrite
    kubectl label node "$CLIENT_NODE" benchmark-role=client --overwrite
    echo "  Server node: $SERVER_NODE"
    echo "  Client node: $CLIENT_NODE"
    echo ""
}

# ================================================================
# Placement validation (for ephemeral pods, validate server only)
# ================================================================
validate_server_placement() {
    local NAMESPACE=$1
    local SCENARIO=$2
    local SERVER_ACTUAL
    SERVER_ACTUAL=$(kubectl get pod -n "$NAMESPACE" -l app=http-server -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)
    if [ -z "$SERVER_ACTUAL" ]; then
        echo "  WARNING: Could not determine server placement for $SCENARIO (ns=$NAMESPACE)"
        return 1
    fi
    echo "  OK $SCENARIO server on $SERVER_ACTUAL"
    return 0
}

# Validate that a file contains valid JSON
validate_json() {
    local FILE=$1
    local LABEL=$2

    if [ ! -s "$FILE" ]; then
        echo "  WARNING: $LABEL output file is empty: $FILE" >&2
        ERRORS=$((ERRORS + 1))
        return 1
    fi

    if ! python3 -m json.tool "$FILE" > /dev/null 2>&1; then
        echo "  WARNING: $LABEL produced invalid JSON: $FILE" >&2
        echo "  Renaming to ${FILE}.corrupted.log" >&2
        mv "$FILE" "${FILE}.corrupted.log"
        ERRORS=$((ERRORS + 1))
        return 1
    fi

    echo "  OK $LABEL output validated as valid JSON"
    return 0
}

# Function to run fortio benchmark (ephemeral pod with nodeSelector)
run_fortio_benchmark() {
    local SCENARIO=$1
    local NAMESPACE=$2
    local SERVICE=$3
    local TRIAL=$4
    local OUTPUT_PREFIX="$RESULTS_DIR/${SCENARIO}"

    echo "----------------------------------------"
    echo "Running: $SCENARIO (trial ${TRIAL}/${TRIALS})"
    echo "Service: $SERVICE (namespace: $NAMESPACE)"
    echo "Duration: ${DURATION}s | Connections: $CONNECTIONS | QPS: $QPS"
    echo "----------------------------------------"

    # Run fortio load test with nodeSelector for client placement
    kubectl run "fortio-bench-${SCENARIO}-t${TRIAL}" \
        --image=fortio/fortio \
        --restart=Never \
        --rm=true \
        -i \
        --timeout=300s \
        -n "$NAMESPACE" \
        --overrides='{"spec":{"nodeSelector":{"benchmark-role":"client"}}}' \
        -- load \
        -c "$CONNECTIONS" \
        -qps "$QPS" \
        -t "${DURATION}s" \
        -json - \
        "http://$SERVICE/" \
        > "${OUTPUT_PREFIX}_run${TRIAL}_raw.json" \
        2> "${OUTPUT_PREFIX}_run${TRIAL}_stderr.log"

    validate_json "${OUTPUT_PREFIX}_run${TRIAL}_raw.json" "${SCENARIO}_run${TRIAL}"

    echo "  OK $SCENARIO trial $TRIAL completed"
    echo ""
}

# Function to run warmup (ephemeral pod, discarded)
run_warmup() {
    local SCENARIO=$1
    local NAMESPACE=$2
    local SERVICE=$3

    echo "  Warmup: $SCENARIO @ ${CONNECTIONS}c for 10s (discarded)..."
    kubectl run "fortio-warmup-${SCENARIO}" \
        --image=fortio/fortio \
        --restart=Never \
        --rm=true \
        -i \
        --timeout=120s \
        -n "$NAMESPACE" \
        --overrides='{"spec":{"nodeSelector":{"benchmark-role":"client"}}}' \
        -- load \
        -c "$CONNECTIONS" \
        -qps 0 \
        -t 10s \
        "http://$SERVICE/" \
        > /dev/null 2>&1
    sleep 5
}

# Function to collect pod resource usage
collect_resource_metrics() {
    local SCENARIO=$1
    local NAMESPACE=$2
    local OUTPUT_FILE="$RESULTS_DIR/${SCENARIO}_resources.txt"

    echo "Collecting resource metrics for $SCENARIO..."

    # Pod resource usage
    if ! kubectl top pods -n "$NAMESPACE" --no-headers > "$OUTPUT_FILE" 2>&1; then
        echo "  WARNING: kubectl top pods failed for $SCENARIO (Metrics API may not be available)" >&2
        echo "# FAILED: Metrics API not available at collection time" > "$OUTPUT_FILE"
        ERRORS=$((ERRORS + 1))
    fi

    # Container count (sidecar detection)
    echo "" >> "$OUTPUT_FILE"
    echo "# Container layout:" >> "$OUTPUT_FILE"
    kubectl get pods -n "$NAMESPACE" -o custom-columns=NAME:.metadata.name,CONTAINERS:.spec.containers[*].name --no-headers >> "$OUTPUT_FILE"

    echo "  OK Resources collected"
}

# Function to get eBPF statistics
collect_ebpf_stats() {
    local OUTPUT_FILE="$RESULTS_DIR/ebpf_statistics.txt"

    echo "Collecting eBPF statistics..."

    # Get Cilium metrics
    local CILIUM_POD
    CILIUM_POD=$(kubectl get pod -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$CILIUM_POD" ]; then
        kubectl exec -n kube-system "$CILIUM_POD" \
            -- cilium metrics list > "$OUTPUT_FILE" 2>&1 || {
            echo "  WARNING: Failed to collect Cilium metrics" >&2
            echo "# FAILED: Could not collect Cilium metrics" > "$OUTPUT_FILE"
            ERRORS=$((ERRORS + 1))
        }
    else
        echo "  WARNING: No Cilium pod found in kube-system" >&2
        echo "# FAILED: No Cilium pod found" > "$OUTPUT_FILE"
        ERRORS=$((ERRORS + 1))
    fi

    # Get eBPF program count
    echo "" >> "$OUTPUT_FILE"
    echo "=== eBPF Programs ===" >> "$OUTPUT_FILE"
    ssh -i "${SSH_KEY:-~/.ssh/oci_benchmark_key}" "ubuntu@${MASTER_IP:?Set MASTER_IP env var}" \
        "sudo bpftool prog show 2>/dev/null | wc -l" >> "$OUTPUT_FILE" 2>&1 || {
        echo "  WARNING: bpftool unavailable via SSH" >&2
        echo "# bpftool unavailable" >> "$OUTPUT_FILE"
    }

    echo "  OK eBPF stats collected"
}

# ================================================================
# STEP 0: Label nodes for deterministic placement
# ================================================================
echo "STEP 0: Label worker nodes"
echo "--------------------------------------------------"
label_nodes

# ================================================================
# STEP 1: Validate server placement
# ================================================================
echo "STEP 1: Validate server pod placement"
echo "--------------------------------------------------"
validate_server_placement "baseline-http" "baseline"
validate_server_placement "http-benchmark" "istio"
validate_server_placement "cilium-only" "cilium"
echo ""

# ================================================================
# STEP 2: Benchmarks
# ================================================================

echo "=================================================="
echo "PHASE 1: BASELINE (No Service Mesh)"
echo "=================================================="
run_warmup "baseline" "baseline-http" "baseline-http-server"
for T in $(seq 1 $TRIALS); do
    run_fortio_benchmark "baseline" "baseline-http" "baseline-http-server" "$T"
    sleep 5
done
collect_resource_metrics "baseline" "baseline-http"
sleep 10

echo ""
echo "=================================================="
echo "PHASE 2: ISTIO (Sidecar Proxy)"
echo "=================================================="
run_warmup "istio" "http-benchmark" "http-server"
for T in $(seq 1 $TRIALS); do
    run_fortio_benchmark "istio" "http-benchmark" "http-server" "$T"
    sleep 5
done
collect_resource_metrics "istio" "http-benchmark"

# Istio-specific metrics
echo "Collecting Istio sidecar metrics..."
POD=$(kubectl get pod -n http-benchmark -l app=http-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$POD" ]; then
    kubectl exec -n http-benchmark "$POD" -c istio-proxy -- \
        curl -s localhost:15000/stats/prometheus 2>/dev/null \
        | grep -E "istio_requests_total|istio_request_duration" \
        > "$RESULTS_DIR/istio_sidecar_stats.txt" || {
        echo "  WARNING: Failed to collect Istio sidecar stats" >&2
        echo "# FAILED: Could not collect Istio sidecar Prometheus metrics" > "$RESULTS_DIR/istio_sidecar_stats.txt"
        ERRORS=$((ERRORS + 1))
    }
else
    echo "  WARNING: No Istio http-server pod found" >&2
    echo "# FAILED: No http-server pod found in http-benchmark namespace" > "$RESULTS_DIR/istio_sidecar_stats.txt"
    ERRORS=$((ERRORS + 1))
fi
sleep 10

echo ""
echo "=================================================="
echo "PHASE 3: CILIUM (Sidecarless eBPF)"
echo "=================================================="
run_warmup "cilium" "cilium-only" "http-server"
for T in $(seq 1 $TRIALS); do
    run_fortio_benchmark "cilium" "cilium-only" "http-server" "$T"
    sleep 5
done
collect_resource_metrics "cilium" "cilium-only"
collect_ebpf_stats

echo ""
echo "=================================================="
echo "PHASE 4: Node and Cluster Metrics"
echo "=================================================="
echo "Collecting cluster-wide metrics..."
if ! kubectl top nodes > "$RESULTS_DIR/cluster_nodes.txt" 2>&1; then
    echo "  WARNING: kubectl top nodes failed (Metrics API may not be available)" >&2
    echo "# FAILED: Metrics API not available" > "$RESULTS_DIR/cluster_nodes.txt"
    ERRORS=$((ERRORS + 1))
fi
kubectl get pods --all-namespaces -o wide > "$RESULTS_DIR/cluster_pods.txt"
echo "  OK Cluster metrics collected"

echo ""
echo "=================================================="
echo "Benchmark Suite Complete!"
echo "=================================================="
date
echo "Results directory: $RESULTS_DIR"
ls -lh "$RESULTS_DIR"

EXPECTED=$((TRIALS * 3))
ACTUAL=$(ls "$RESULTS_DIR"/*_run*_raw.json 2>/dev/null | wc -l)
echo ""
echo "Expected: $EXPECTED benchmark files (3 scenarios x $TRIALS trials)"
echo "Actual:   $ACTUAL benchmark files"

if [ "$ERRORS" -gt 0 ]; then
    echo ""
    echo "WARNING: $ERRORS data collection issue(s) encountered."
    echo "Review stderr logs and files marked with '# FAILED' for details."
fi

if [ "$ACTUAL" -eq "$EXPECTED" ]; then
    echo ""
    echo "SUCCESS: All $EXPECTED benchmark files produced."
else
    echo ""
    echo "WARNING: Expected $EXPECTED but got $ACTUAL."
fi
