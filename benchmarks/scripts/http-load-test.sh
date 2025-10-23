#!/bin/bash
# shellcheck shell=bash
set -euo pipefail

# HTTP Load Testing Script using Apache Bench and wrk

echo "=== HTTP Load Test ==="

# Configuration
SERVICE_URL="${SERVICE_URL:-http-server.http-benchmark.svc.cluster.local}"
NAMESPACE="${NAMESPACE:-http-benchmark}"
RESULTS_DIR="${RESULTS_DIR:-../results}"
TEST_DURATION="${TEST_DURATION:-60}"
CONCURRENT_CONNECTIONS="${CONCURRENT_CONNECTIONS:-100}"
THREADS="${THREADS:-4}"
WARMUP_DURATION="${WARMUP_DURATION:-10}"
COOLDOWN_DURATION="${COOLDOWN_DURATION:-5}"
MESH_TYPE="${MESH_TYPE:-baseline}"

# Validate inputs
if [[ ! "${NAMESPACE}" =~ ^[a-z0-9-]+$ ]]; then
    echo "Error: Invalid namespace format" >&2
    exit 1
fi

# Create results directory
mkdir -p "${RESULTS_DIR}"

# Get timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${RESULTS_DIR}/http_test_${TIMESTAMP}.json"

echo "Testing HTTP service: ${SERVICE_URL}"
echo "Namespace: ${NAMESPACE}"
echo "Mesh Type: ${MESH_TYPE}"
echo "Duration: ${TEST_DURATION}s"
echo "Concurrent connections: ${CONCURRENT_CONNECTIONS}"
echo "Threads: ${THREADS}"
echo "Warm-up: ${WARMUP_DURATION}s, Cool-down: ${COOLDOWN_DURATION}s"
echo ""

# Health check - wait for pods to be ready
echo "Checking pod readiness..."
if ! kubectl wait --for=condition=ready pod -l app=http-server -n "${NAMESPACE}" --timeout=300s 2>/dev/null; then
    echo "Warning: Pods may not be ready, but continuing anyway..."
fi

# Verify service is accessible
echo "Verifying service connectivity..."
if ! kubectl run test-curl --image=curlimages/curl:latest --rm -i --restart=Never -n "${NAMESPACE}" -- curl -s --max-time 5 "http://${SERVICE_URL}/" &> /dev/null; then
    echo "ERROR: Service ${SERVICE_URL} is not accessible!" >&2
    exit 1
fi
echo "Service is accessible"
echo ""

# Warm-up period
echo "Running warm-up period (${WARMUP_DURATION}s)..."
if command -v wrk &> /dev/null; then
    wrk -t2 -c10 -d"${WARMUP_DURATION}s" --timeout 10s "http://${SERVICE_URL}/" > /dev/null 2>&1 || true
else
    echo "wrk not available for warm-up, skipping..."
fi
echo "Warm-up complete"
echo ""

# Check if wrk is installed
if command -v wrk &> /dev/null; then
    echo "Running wrk benchmark..."
    wrk -t"${THREADS}" -c"${CONCURRENT_CONNECTIONS}" -d"${TEST_DURATION}s" \
        --latency \
        --timeout 10s \
        "http://${SERVICE_URL}/" | tee "${RESULTS_DIR}/http_wrk_${TIMESTAMP}.txt"
else
    echo "wrk not found, installing..."
    sudo apt-get update && sudo apt-get install -y wrk
fi

# Run Apache Bench test
if command -v ab &> /dev/null; then
    echo "Running Apache Bench..."
    ab -n 10000 -c "${CONCURRENT_CONNECTIONS}" \
        -g "${RESULTS_DIR}/http_ab_${TIMESTAMP}.tsv" \
        "http://${SERVICE_URL}/" | tee "${RESULTS_DIR}/http_ab_${TIMESTAMP}.txt"
else
    echo "Apache Bench not found, installing..."
    sudo apt-get install -y apache2-utils
fi

# Cool-down period
echo ""
echo "Running cool-down period (${COOLDOWN_DURATION}s)..."
sleep "${COOLDOWN_DURATION}"
echo "Cool-down complete"
echo ""

# Collect Kubernetes metrics
echo "Collecting Kubernetes metrics..."
kubectl top pods -n "${NAMESPACE}" > "${RESULTS_DIR}/http_k8s_metrics_${TIMESTAMP}.txt" 2>/dev/null || echo "kubectl top not available"

# Parse wrk output for metrics
REQUESTS_PER_SEC=0
AVG_LATENCY_MS=0

if [ -f "${RESULTS_DIR}/http_wrk_${TIMESTAMP}.txt" ]; then
    REQUESTS_PER_SEC=$(grep "Requests/sec:" "${RESULTS_DIR}/http_wrk_${TIMESTAMP}.txt" | awk '{print $2}' || echo "0")
    AVG_LATENCY=$(grep "Latency" "${RESULTS_DIR}/http_wrk_${TIMESTAMP}.txt" | head -1 | awk '{print $2}')

    # Convert latency to milliseconds
    if [[ "${AVG_LATENCY}" == *"ms" ]]; then
        AVG_LATENCY_MS="${AVG_LATENCY%ms}"
    elif [[ "${AVG_LATENCY}" == *"s" ]]; then
        AVG_LATENCY_SEC="${AVG_LATENCY%s}"
        AVG_LATENCY_MS=$(awk "BEGIN {printf \"%.2f\", ${AVG_LATENCY_SEC} * 1000}")
    elif [[ "${AVG_LATENCY}" == *"us" ]]; then
        AVG_LATENCY_US="${AVG_LATENCY%us}"
        AVG_LATENCY_MS=$(awk "BEGIN {printf \"%.2f\", ${AVG_LATENCY_US} / 1000}")
    fi
fi

# Generate JSON summary with metrics
cat > "${OUTPUT_FILE}" << EOF
{
  "test_type": "http",
  "mesh_type": "${MESH_TYPE}",
  "timestamp": "${TIMESTAMP}",
  "service_url": "${SERVICE_URL}",
  "namespace": "${NAMESPACE}",
  "duration": ${TEST_DURATION},
  "concurrent_connections": ${CONCURRENT_CONNECTIONS},
  "threads": ${THREADS},
  "warmup_duration": ${WARMUP_DURATION},
  "cooldown_duration": ${COOLDOWN_DURATION},
  "metrics": {
    "requests_per_sec": ${REQUESTS_PER_SEC},
    "avg_latency_ms": ${AVG_LATENCY_MS}
  },
  "results_files": {
    "wrk": "http_wrk_${TIMESTAMP}.txt",
    "ab": "http_ab_${TIMESTAMP}.txt",
    "k8s_metrics": "http_k8s_metrics_${TIMESTAMP}.txt"
  }
}
EOF

echo ""
echo "=== Test Results Summary ==="
echo "Requests/sec: ${REQUESTS_PER_SEC}"
echo "Avg Latency: ${AVG_LATENCY_MS}ms"
echo ""
echo "Results saved to: ${OUTPUT_FILE}"
echo "=== HTTP Load Test Complete ==="
