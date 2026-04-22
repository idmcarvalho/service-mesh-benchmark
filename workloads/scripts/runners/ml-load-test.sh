#!/bin/bash
set -e

# ML Inference Load Test Script using Fortio
# Sends HTTP POST requests to the ML inference server (POST /predict) from inside
# the cluster via kubectl exec, so eBPF probes capture the traffic.
#
# Two test phases:
#   Phase 1 — Throughput test: standard concurrency sweep at medium payload (16KB)
#   Phase 2 — Payload size sweep: 1KB / 16KB / 128KB at fixed concurrency=10
#             Reveals how mesh overhead scales with inference batch size.

# Configuration from environment variables
MESH_TYPE="${MESH_TYPE:-baseline}"
NAMESPACE="${NAMESPACE:-default}"
TEST_DURATION="${TEST_DURATION:-60}"
CONCURRENT_CONNECTIONS="${CONCURRENT_CONNECTIONS:-10}"
SERVICE_URL="${SERVICE_URL:-http://http-server:8080/predict}"
RESULTS_DIR="${RESULTS_DIR:-./results}"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "========================================="
echo "ML Inference Load Test"
echo "========================================="
echo "Mesh Type:   $MESH_TYPE"
echo "Namespace:   $NAMESPACE"
echo "Duration:    ${TEST_DURATION}s"
echo "Connections: $CONCURRENT_CONNECTIONS"
echo "Service URL: $SERVICE_URL"
echo "Output dir:  $RESULTS_DIR"
echo "========================================="

mkdir -p "$RESULTS_DIR"

# ----------------------------------------------------------------
# Generate feature vector payloads inside the client pod
# Sizes: small=1KB (~12 samples), medium=16KB (~200 samples), large=128KB (~1600 samples)
# Each payload is a JSON POST body: {"features": [[f1..f20], ...]}
# ----------------------------------------------------------------
generate_payloads() {
    kubectl exec "fortio-client" -n "$NAMESPACE" -- python3 - <<'PYEOF'
import json, os

N_FEATURES = 20

def make_payload(n_samples):
    import random
    random.seed(42)
    features = [[round(random.gauss(0, 1), 4) for _ in range(N_FEATURES)]
                for _ in range(n_samples)]
    return json.dumps({"features": features}).encode()

sizes = {"small": 12, "medium": 200, "large": 1600}
for name, n in sizes.items():
    payload = make_payload(n)
    path = f"/tmp/ml_payload_{name}.json"
    with open(path, "wb") as f:
        f.write(payload)
    print(f"Generated {name}: {len(payload)} bytes ({n} samples) -> {path}")
PYEOF
}

echo "Generating payloads inside fortio-client..."
generate_payloads

# ----------------------------------------------------------------
# Helper: run one Fortio POST benchmark and annotate JSON
# ----------------------------------------------------------------
run_ml_trial() {
    local LABEL=$1
    local CONNECTIONS=$2
    local PAYLOAD_SIZE=$3   # small | medium | large
    local OUTPUT_FILE="${RESULTS_DIR}/${MESH_TYPE}_ml_${LABEL}_${TIMESTAMP}.json"
    local STDERR_LOG="${OUTPUT_FILE%.json}_stderr.log"
    local PAYLOAD_PATH="/tmp/ml_payload_${PAYLOAD_SIZE}.json"

    echo "  Running: $LABEL (c=${CONNECTIONS} payload=${PAYLOAD_SIZE}) -> $SERVICE_URL"

    kubectl exec "fortio-client" -n "$NAMESPACE" -- \
        fortio load \
        -c "$CONNECTIONS" \
        -qps 0 \
        -t "${TEST_DURATION}s" \
        -content-type "application/json" \
        -payload "@${PAYLOAD_PATH}" \
        -json - \
        "$SERVICE_URL" \
        > "$OUTPUT_FILE" \
        2> "$STDERR_LOG"

    if [ ! -s "$OUTPUT_FILE" ]; then
        echo "  WARNING: empty output for $LABEL" >&2
        return 1
    fi
    if ! python3 -m json.tool "$OUTPUT_FILE" > /dev/null 2>&1; then
        echo "  WARNING: invalid JSON for $LABEL" >&2
        mv "$OUTPUT_FILE" "${OUTPUT_FILE}.corrupted.log"
        return 1
    fi

    # Annotate with benchmark metadata
    local CURRENT_TIME
    CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    python3 - <<PYEOF
import json
with open("$OUTPUT_FILE") as f:
    result = json.load(f)
result["test_type"] = "ml_inference"
result["mesh_type"] = "$MESH_TYPE"
result["namespace"] = "$NAMESPACE"
result["benchmark_timestamp"] = "$CURRENT_TIME"
result.setdefault("configuration", {}).update({
    "service_url": "$SERVICE_URL",
    "concurrent_connections": int("$CONNECTIONS"),
    "payload_size": "$PAYLOAD_SIZE",
    "duration_seconds": int("$TEST_DURATION"),
})
with open("$OUTPUT_FILE", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

    echo "  OK $LABEL -> $OUTPUT_FILE"
}

# ----------------------------------------------------------------
# Phase 1: Throughput sweep at medium payload (16KB ~200 samples)
# Same concurrency levels as HTTP benchmark for direct comparison
# ----------------------------------------------------------------
echo ""
echo "Phase 1: Throughput sweep (payload=medium/16KB)"
echo "----------------------------------------------------------------"
for C in 10 50 100; do
    run_ml_trial "throughput_${C}c" "$C" "medium"
    sleep 3
done

# ----------------------------------------------------------------
# Phase 2: Payload size sweep at fixed concurrency=10
# Reveals how mesh overhead (absolute ms) scales with payload size
# ----------------------------------------------------------------
echo ""
echo "Phase 2: Payload size sweep (connections=10)"
echo "----------------------------------------------------------------"
for SIZE in small medium large; do
    run_ml_trial "payload_${SIZE}" 10 "$SIZE"
    sleep 3
done

echo ""
echo "========================================="
echo "ML inference tests complete."
echo "Results: $RESULTS_DIR"
echo "========================================="

exit 0
