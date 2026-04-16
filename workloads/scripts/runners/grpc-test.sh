#!/bin/bash
set -e

# gRPC Load Test Script using Fortio (via kubectl exec)
# Runs Fortio's built-in gRPC load generator from inside the cluster so eBPF
# socket probes capture the traffic. Consistent toolchain with HTTP benchmarks.
#
# Two test phases:
#   Phase 1 — Standard concurrency sweep (same as HTTP: 10/50/100 connections)
#   Phase 2 — Streams-per-connection sweep (1/5/10 streams @ fixed 10 connections)
#             Captures gRPC multiplexing behaviour invisible to HTTP/1.1 benchmarks.

# Configuration from environment variables
MESH_TYPE="${MESH_TYPE:-baseline}"
NAMESPACE="${NAMESPACE:-default}"
TEST_DURATION="${TEST_DURATION:-60}"
CONCURRENT_CONNECTIONS="${CONCURRENT_CONNECTIONS:-50}"
RESULTS_DIR="${RESULTS_DIR:-./results}"

# Fortio gRPC ping target (host:port, no scheme)
GRPC_TARGET="${GRPC_TARGET:-http-server:8079}"

# Generate timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "========================================="
echo "gRPC Load Test (Fortio via kubectl exec)"
echo "========================================="
echo "Mesh Type:   $MESH_TYPE"
echo "Namespace:   $NAMESPACE"
echo "Duration:    ${TEST_DURATION}s"
echo "Connections: $CONCURRENT_CONNECTIONS"
echo "gRPC Target: $GRPC_TARGET"
echo "Output dir:  $RESULTS_DIR"
echo "========================================="

mkdir -p "$RESULTS_DIR"

# ----------------------------------------------------------------
# Helper: run one Fortio gRPC benchmark and annotate the JSON
# ----------------------------------------------------------------
run_grpc_trial() {
    local LABEL=$1          # e.g. "grpc_50c" or "grpc_streams_5s"
    local CONNECTIONS=$2
    local STREAMS=$3        # streams per connection (Fortio -grpc-streams)
    local OUTPUT_FILE="${RESULTS_DIR}/${MESH_TYPE}_${LABEL}_${TIMESTAMP}.json"
    local STDERR_LOG="${OUTPUT_FILE%.json}_stderr.log"

    echo "  Running: $LABEL (c=${CONNECTIONS} streams=${STREAMS}) -> $GRPC_TARGET"

    kubectl exec "fortio-client" -n "$NAMESPACE" -- \
        fortio load \
        -grpc \
        -grpc-ping-delay 0 \
        -s "$STREAMS" \
        -c "$CONNECTIONS" \
        -qps 0 \
        -t "${TEST_DURATION}s" \
        -json - \
        "$GRPC_TARGET" \
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
result["test_type"] = "grpc"
result["mesh_type"] = "$MESH_TYPE"
result["namespace"] = "$NAMESPACE"
result["benchmark_timestamp"] = "$CURRENT_TIME"
result.setdefault("configuration", {}).update({
    "grpc_target": "$GRPC_TARGET",
    "concurrent_connections": int("$CONNECTIONS"),
    "streams_per_connection": int("$STREAMS"),
    "duration_seconds": int("$TEST_DURATION"),
})
with open("$OUTPUT_FILE", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

    echo "  OK $LABEL -> $OUTPUT_FILE"
}

# ----------------------------------------------------------------
# Phase 1: Standard concurrency sweep (mirrors HTTP benchmark)
# ----------------------------------------------------------------
echo ""
echo "Phase 1: Concurrency sweep (streams=1)"
echo "----------------------------------------------------------------"
run_grpc_trial "grpc_${CONCURRENT_CONNECTIONS}c" "$CONCURRENT_CONNECTIONS" 1
sleep 3

# ----------------------------------------------------------------
# Phase 2: Streams-per-connection sweep at fixed 10 connections
# Reveals how multiplexing interacts with each mesh's data plane
# ----------------------------------------------------------------
echo ""
echo "Phase 2: Streams-per-connection sweep (connections=10)"
echo "----------------------------------------------------------------"
for STREAMS in 1 5 10; do
    run_grpc_trial "grpc_streams_${STREAMS}s" 10 "$STREAMS"
    sleep 3
done

echo ""
echo "========================================="
echo "gRPC tests complete."
echo "Results: $RESULTS_DIR"
echo "========================================="

exit 0
