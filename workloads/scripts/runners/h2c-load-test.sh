#!/bin/bash
set -e

# HTTP/2 (h2c) Load Test Script using Fortio
# Uses Fortio's native -h2 flag for cleartext HTTP/2 benchmarking.
# Reads configuration from environment variables and outputs JSON results.

# Configuration from environment variables
MESH_TYPE="${MESH_TYPE:-baseline}"
NAMESPACE="${NAMESPACE:-default}"
TEST_DURATION="${TEST_DURATION:-60}"
CONCURRENT_CONNECTIONS="${CONCURRENT_CONNECTIONS:-100}"
SERVICE_URL="${SERVICE_URL:-}"
RESULTS_DIR="${RESULTS_DIR:-./results}"

# Generate timestamp and output file
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${RESULTS_DIR}/${MESH_TYPE}_http2_${TIMESTAMP}.json"
STDERR_LOG="${RESULTS_DIR}/${MESH_TYPE}_http2_${TIMESTAMP}_stderr.log"

echo "========================================="
echo "HTTP/2 (h2c) Load Test"
echo "========================================="
echo "Mesh Type:   $MESH_TYPE"
echo "Namespace:   $NAMESPACE"
echo "Duration:    ${TEST_DURATION}s"
echo "Connections: $CONCURRENT_CONNECTIONS"
echo "Service URL: $SERVICE_URL"
echo "Output:      $OUTPUT_FILE"
echo "========================================="

# Ensure results directory exists
mkdir -p "$RESULTS_DIR"

# Require SERVICE_URL
if [ -z "$SERVICE_URL" ]; then
    echo "ERROR: SERVICE_URL environment variable is required"
    echo "Example: SERVICE_URL=http://http-server.${NAMESPACE}.svc.cluster.local:8080/"
    exit 1
fi

# Convert http:// to h2c:// so Fortio uses cleartext HTTP/2
H2C_URL="${SERVICE_URL/http:\/\//h2c://}"

echo "Starting HTTP/2 load test (h2c URL: $H2C_URL)..."

# Run Fortio via kubectl exec so eBPF probes capture the traffic
kubectl exec "fortio-client" -n "$NAMESPACE" -- \
    fortio load \
    -h2 \
    -c "$CONCURRENT_CONNECTIONS" \
    -qps 0 \
    -t "${TEST_DURATION}s" \
    -json - \
    "$H2C_URL" \
    > "$OUTPUT_FILE" \
    2> "$STDERR_LOG"

# Validate JSON output
if [ ! -s "$OUTPUT_FILE" ]; then
    echo "ERROR: Fortio produced empty output" >&2
    exit 1
fi

if ! python3 -m json.tool "$OUTPUT_FILE" > /dev/null 2>&1; then
    echo "ERROR: Fortio produced invalid JSON" >&2
    mv "$OUTPUT_FILE" "${OUTPUT_FILE}.corrupted.log"
    exit 1
fi

# Inject benchmark metadata into the Fortio JSON output
CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
ANNOTATED_FILE="${OUTPUT_FILE}.tmp"

python3 - <<PYEOF
import json, sys
with open("$OUTPUT_FILE") as f:
    result = json.load(f)
result["test_type"] = "http2"
result["mesh_type"] = "$MESH_TYPE"
result["namespace"] = "$NAMESPACE"
result["benchmark_timestamp"] = "$CURRENT_TIME"
result.setdefault("configuration", {})["protocol"] = "h2c"
result["configuration"]["concurrent_connections"] = int("$CONCURRENT_CONNECTIONS")
result["configuration"]["duration_seconds"] = int("$TEST_DURATION")
result["configuration"]["service_url"] = "$H2C_URL"
with open("${ANNOTATED_FILE}", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

mv "$ANNOTATED_FILE" "$OUTPUT_FILE"

echo "========================================="
echo "Results saved to: $OUTPUT_FILE"
echo "========================================="

exit 0
