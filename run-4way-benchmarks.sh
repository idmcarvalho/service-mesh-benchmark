#!/bin/bash
# Service Mesh Benchmark: Sidecar vs Sidecarless
# 5 scenarios, identical traffic pattern: client -> ClusterIP:8080 -> backend
# Backend: Fortio server | Load generator: Fortio client
#
# Scenarios:
#   1. baseline      - No mesh (control group)
#   2. cilium-ebpf   - Sidecarless: Cilium eBPF L3/L4 only (kernel-level)
#   3. cilium-l7     - Sidecarless: Cilium per-node Envoy L7 (CiliumNetworkPolicy)
#   4. istio-sidecar - Sidecar: Istio per-pod Envoy L7
#   5. istio-ambient - Sidecarless: Istio per-node ztunnel L4
#
# Methodology:
#   - Server pods pinned to one worker node, client pods to another (deterministic cross-node path)
#   - 10s warmup run (discarded) before each scenario
#   - 5 independent trials per concurrency level for statistical validity

set -eo pipefail

export KUBECONFIG=~/.kube/config.oci
RESULTS_DIR="./benchmarks/results"
MASTER_IP="${MASTER_IP:?Set MASTER_IP env var to the master node public IP}"
SSH_KEY="${SSH_KEY:-~/.ssh/oci_benchmark_key}"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
DURATION=30
QPS=0  # unlimited
CONCURRENCY_LEVELS=(10 50 100)
TRIALS=5
ERRORS=0

mkdir -p "$RESULTS_DIR"

# 5 scenarios - parallel arrays (all use identical service endpoint)
SCENARIO_NAMES=(baseline cilium-ebpf cilium-l7 istio-sidecar istio-ambient)
SCENARIO_NAMESPACES=(baseline-http cilium-ebpf cilium-l7 http-benchmark istio-ambient)
SCENARIO_TYPES=("none" "sidecarless-l4" "sidecarless-l7" "sidecar-l7" "sidecarless-l4")
# ALL scenarios use the same URL pattern: http://http-server:8080/
# This is the key fairness guarantee - identical east-west traffic path
SCENARIO_URLS=(
    "http://http-server:8080/"
    "http://http-server:8080/"
    "http://http-server:8080/"
    "http://http-server:8080/"
    "http://http-server:8080/"
)

echo "================================================================"
echo "Service Mesh Benchmark: Sidecar vs Sidecarless"
echo "================================================================"
echo "Backend: Fortio server | All scenarios: client -> svc:8080 -> backend"
echo ""
echo "  1. baseline      | No mesh          | Control group"
echo "  2. cilium-ebpf   | Sidecarless L3/L4| Cilium eBPF (kernel)"
echo "  3. cilium-l7     | Sidecarless L7   | Cilium per-node Envoy"
echo "  4. istio-sidecar | SIDECAR L7       | Istio per-pod Envoy"
echo "  5. istio-ambient | Sidecarless L4   | Istio per-node ztunnel"
echo ""
echo "Concurrency: ${CONCURRENCY_LEVELS[*]} | Duration: ${DURATION}s | QPS: unlimited"
echo "Trials: $TRIALS per configuration | Warmup: 10s (discarded)"
echo "================================================================"
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
# Placement validation
# ================================================================
validate_placement() {
    echo "Validating pod placement..."
    local FAILED=0
    for i in "${!SCENARIO_NAMES[@]}"; do
        local NS="${SCENARIO_NAMESPACES[$i]}"
        local NAME="${SCENARIO_NAMES[$i]}"
        local CLIENT_ACTUAL
        CLIENT_ACTUAL=$(kubectl get pod fortio-client -n "$NS" -o jsonpath='{.spec.nodeName}' 2>/dev/null)
        local SERVER_ACTUAL
        SERVER_ACTUAL=$(kubectl get pod -n "$NS" -l app=http-server -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)
        if [ -z "$CLIENT_ACTUAL" ] || [ -z "$SERVER_ACTUAL" ]; then
            echo "  WARNING: Could not determine placement for $NAME (ns=$NS)"
            FAILED=1
            continue
        fi
        if [ "$CLIENT_ACTUAL" = "$SERVER_ACTUAL" ]; then
            echo "  FATAL: client and server co-located on $CLIENT_ACTUAL in $NS ($NAME)"
            FAILED=1
        else
            echo "  OK $NAME: client=$CLIENT_ACTUAL server=$SERVER_ACTUAL"
        fi
    done
    if [ "$FAILED" -eq 1 ]; then
        echo "FATAL: Placement validation failed. Aborting."
        exit 1
    fi
    echo ""
}

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
        mv "$FILE" "${FILE}.corrupted.log"
        ERRORS=$((ERRORS + 1))
        return 1
    fi

    echo "  OK $LABEL validated"
    return 0
}

deploy_fortio() {
    local NAMESPACE=$1
    local POD_NAME="fortio-client"

    if kubectl get pod "$POD_NAME" -n "$NAMESPACE" --no-headers 2>/dev/null | grep -q Running; then
        echo "  Fortio client already running in $NAMESPACE"
        return 0
    fi

    kubectl delete pod "$POD_NAME" -n "$NAMESPACE" --ignore-not-found --wait=false 2>/dev/null || true
    sleep 2

    kubectl run "$POD_NAME" \
        --image=fortio/fortio:latest \
        --restart=Never \
        -n "$NAMESPACE" \
        --labels="app=fortio-client" \
        --overrides='{"spec":{"nodeSelector":{"benchmark-role":"client"}}}' \
        -- server

    echo "  Waiting for fortio-client in $NAMESPACE..."
    kubectl wait --for=condition=Ready pod/"$POD_NAME" -n "$NAMESPACE" --timeout=120s
    echo "  Fortio client ready in $NAMESPACE"
}

run_fortio_benchmark() {
    local SCENARIO=$1
    local NAMESPACE=$2
    local TARGET_URL=$3
    local CONNECTIONS=$4
    local TRIAL=$5
    local OUTPUT_FILE="$RESULTS_DIR/bench_${SCENARIO}_${CONNECTIONS}c_run${TRIAL}.json"

    echo "  Running: $SCENARIO @ ${CONNECTIONS}c trial ${TRIAL}/${TRIALS} -> $TARGET_URL"

    kubectl exec "fortio-client" -n "$NAMESPACE" -- \
        fortio load \
        -c "$CONNECTIONS" \
        -qps "$QPS" \
        -t "${DURATION}s" \
        -json - \
        "$TARGET_URL" \
        > "$OUTPUT_FILE" \
        2> "$RESULTS_DIR/bench_${SCENARIO}_${CONNECTIONS}c_run${TRIAL}_stderr.log"

    validate_json "$OUTPUT_FILE" "${SCENARIO}_${CONNECTIONS}c_run${TRIAL}"
}

run_warmup() {
    local SCENARIO=$1
    local NAMESPACE=$2
    local TARGET_URL=$3

    echo "  Warmup: $SCENARIO @ 100c for 10s (discarded)..."
    kubectl exec "fortio-client" -n "$NAMESPACE" -- \
        fortio load -c 100 -qps 0 -t 10s "$TARGET_URL" > /dev/null 2>&1
    sleep 5
}

collect_resource_metrics() {
    local SCENARIO=$1
    local NAMESPACE=$2
    local OUTPUT_FILE="$RESULTS_DIR/${SCENARIO}_resources.txt"

    echo "  Collecting resource metrics for $SCENARIO..."
    kubectl top pods -n "$NAMESPACE" --no-headers > "$OUTPUT_FILE" 2>&1 || {
        echo "# Metrics API unavailable" > "$OUTPUT_FILE"
        ERRORS=$((ERRORS + 1))
    }
    echo "" >> "$OUTPUT_FILE"
    echo "# Container layout:" >> "$OUTPUT_FILE"
    kubectl get pods -n "$NAMESPACE" -o custom-columns=NAME:.metadata.name,CONTAINERS:.spec.containers[*].name,READY:.status.containerStatuses[*].ready --no-headers >> "$OUTPUT_FILE"
}

collect_infrastructure_metrics() {
    echo "Collecting infrastructure metrics..."

    # Istio sidecar Envoy stats
    ISTIO_POD=$(kubectl get pod -n http-benchmark -l app=http-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$ISTIO_POD" ]; then
        kubectl exec -n http-benchmark "$ISTIO_POD" -c istio-proxy -- \
            curl -s localhost:15000/stats/prometheus 2>/dev/null \
            | grep -E "istio_requests_total|istio_request_duration" \
            > "$RESULTS_DIR/istio_sidecar_stats.txt" || {
            echo "# Could not collect Istio sidecar stats" > "$RESULTS_DIR/istio_sidecar_stats.txt"
            ERRORS=$((ERRORS + 1))
        }
    fi

    # Cilium eBPF stats
    CILIUM_POD=$(kubectl get pod -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$CILIUM_POD" ]; then
        kubectl exec -n kube-system "$CILIUM_POD" -- cilium metrics list > "$RESULTS_DIR/ebpf_statistics.txt" 2>&1 || {
            echo "# Could not collect Cilium metrics" > "$RESULTS_DIR/ebpf_statistics.txt"
            ERRORS=$((ERRORS + 1))
        }
    fi

    # Cilium L7 proxy stats
    if [ -n "$CILIUM_POD" ]; then
        kubectl exec -n kube-system "$CILIUM_POD" -- cilium-dbg proxy stats > "$RESULTS_DIR/cilium_l7_proxy_stats.txt" 2>&1 || {
            echo "# Could not collect Cilium L7 proxy stats" > "$RESULTS_DIR/cilium_l7_proxy_stats.txt"
        }
    fi

    # CiliumNetworkPolicy status for cilium-l7
    kubectl get ciliumnetworkpolicy -n cilium-l7 -o yaml > "$RESULTS_DIR/cilium_l7_policy.yaml" 2>&1 || true

    # Cluster nodes
    kubectl top nodes > "$RESULTS_DIR/cluster_nodes.txt" 2>&1 || {
        echo "# Metrics API unavailable" > "$RESULTS_DIR/cluster_nodes.txt"
        ERRORS=$((ERRORS + 1))
    }

    # All pods
    kubectl get pods --all-namespaces -o wide > "$RESULTS_DIR/cluster_pods.txt"

    # Namespace labels
    echo "=== Namespace Labels ===" > "$RESULTS_DIR/namespace_labels.txt"
    for NS in baseline-http cilium-ebpf cilium-l7 http-benchmark istio-ambient; do
        echo "--- $NS ---" >> "$RESULTS_DIR/namespace_labels.txt"
        kubectl get namespace "$NS" --show-labels --no-headers >> "$RESULTS_DIR/namespace_labels.txt" 2>&1 || echo "  $NS: not found" >> "$RESULTS_DIR/namespace_labels.txt"
    done

    echo "  OK infrastructure metrics collected"
}

# ================================================================
# STEP 0: Label nodes for deterministic placement
# ================================================================
echo "STEP 0: Label worker nodes"
echo "----------------------------------------------------------------"
label_nodes

# ================================================================
# STEP 1: Deploy fortio clients
# ================================================================
echo "STEP 1: Deploy fortio clients to all namespaces"
echo "----------------------------------------------------------------"

for i in "${!SCENARIO_NAMES[@]}"; do
    echo "  Deploying to ${SCENARIO_NAMESPACES[$i]}..."
    deploy_fortio "${SCENARIO_NAMESPACES[$i]}"
done

echo ""
sleep 5

# ================================================================
# STEP 2: Validate placement
# ================================================================
echo "STEP 2: Validate pod placement (client != server node)"
echo "----------------------------------------------------------------"
validate_placement

# ================================================================
# STEP 3: Run benchmarks
# ================================================================
TOTAL_RUNS=$(( ${#SCENARIO_NAMES[@]} * ${#CONCURRENCY_LEVELS[@]} * TRIALS ))
echo "STEP 3: Run benchmarks (${#SCENARIO_NAMES[@]} scenarios x ${#CONCURRENCY_LEVELS[@]} concurrency x ${TRIALS} trials = ${TOTAL_RUNS} runs)"
echo "================================================================"

for i in "${!SCENARIO_NAMES[@]}"; do
    SCENARIO="${SCENARIO_NAMES[$i]}"
    NAMESPACE="${SCENARIO_NAMESPACES[$i]}"
    TARGET_URL="${SCENARIO_URLS[$i]}"

    echo ""
    echo ">>> ${SCENARIO^^} [${SCENARIO_TYPES[$i]}] namespace=$NAMESPACE"
    echo "    target=$TARGET_URL"

    # Warmup run (discarded)
    run_warmup "$SCENARIO" "$NAMESPACE" "$TARGET_URL"

    for C in "${CONCURRENCY_LEVELS[@]}"; do
        for T in $(seq 1 $TRIALS); do
            run_fortio_benchmark "$SCENARIO" "$NAMESPACE" "$TARGET_URL" "$C" "$T"
            sleep 5
        done
    done

    collect_resource_metrics "$SCENARIO" "$NAMESPACE"
done

# ================================================================
# STEP 4: Infrastructure metrics
# ================================================================
echo ""
echo "STEP 4: Collect infrastructure metrics"
echo "----------------------------------------------------------------"
collect_infrastructure_metrics

# ================================================================
# STEP 5: Cleanup
# ================================================================
echo ""
echo "STEP 5: Cleanup fortio clients"
echo "----------------------------------------------------------------"
for i in "${!SCENARIO_NAMES[@]}"; do
    kubectl delete pod fortio-client -n "${SCENARIO_NAMESPACES[$i]}" --ignore-not-found || true
done

# ================================================================
# SUMMARY
# ================================================================
echo ""
echo "================================================================"
echo "Benchmark Complete!"
echo "================================================================"
date
echo ""
echo "Results: $RESULTS_DIR"
ls -lh "$RESULTS_DIR"/bench_*.json 2>/dev/null || echo "  No benchmark JSON files found"
echo ""
EXPECTED=$(( ${#SCENARIO_NAMES[@]} * ${#CONCURRENCY_LEVELS[@]} * TRIALS ))
ACTUAL=$(ls "$RESULTS_DIR"/bench_*.json 2>/dev/null | wc -l)
echo "Expected: $EXPECTED benchmark files (${#SCENARIO_NAMES[@]} scenarios x ${#CONCURRENCY_LEVELS[@]} concurrency x ${TRIALS} trials)"
echo "Actual:   $ACTUAL benchmark files"

if [ "$ERRORS" -gt 0 ]; then
    echo ""
    echo "WARNING: $ERRORS data collection issue(s)."
fi

if [ "$ACTUAL" -eq "$EXPECTED" ]; then
    echo ""
    echo "SUCCESS: All $EXPECTED benchmark files produced."
else
    echo ""
    echo "WARNING: Expected $EXPECTED but got $ACTUAL."
fi
