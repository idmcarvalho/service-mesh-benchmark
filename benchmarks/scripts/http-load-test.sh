#!/bin/bash
set -e

# HTTP Load Testing Script using Apache Bench and wrk

echo "=== HTTP Load Test ==="

# Configuration
SERVICE_URL="${SERVICE_URL:-http-server.http-benchmark.svc.cluster.local}"
RESULTS_DIR="${RESULTS_DIR:-../results}"
TEST_DURATION="${TEST_DURATION:-60}"
CONCURRENT_CONNECTIONS="${CONCURRENT_CONNECTIONS:-100}"
THREADS="${THREADS:-4}"

# Create results directory
mkdir -p "$RESULTS_DIR"

# Get timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="$RESULTS_DIR/http_test_${TIMESTAMP}.json"

echo "Testing HTTP service: $SERVICE_URL"
echo "Duration: ${TEST_DURATION}s"
echo "Concurrent connections: $CONCURRENT_CONNECTIONS"
echo "Threads: $THREADS"

# Check if wrk is installed
if command -v wrk &> /dev/null; then
    echo "Running wrk benchmark..."
    wrk -t$THREADS -c$CONCURRENT_CONNECTIONS -d${TEST_DURATION}s \
        --latency \
        --timeout 10s \
        "http://$SERVICE_URL/" | tee "$RESULTS_DIR/http_wrk_${TIMESTAMP}.txt"
else
    echo "wrk not found, installing..."
    sudo apt-get update && sudo apt-get install -y wrk
fi

# Run Apache Bench test
if command -v ab &> /dev/null; then
    echo "Running Apache Bench..."
    ab -n 10000 -c $CONCURRENT_CONNECTIONS \
        -g "$RESULTS_DIR/http_ab_${TIMESTAMP}.tsv" \
        "http://$SERVICE_URL/" | tee "$RESULTS_DIR/http_ab_${TIMESTAMP}.txt"
else
    echo "Apache Bench not found, installing..."
    sudo apt-get install -y apache2-utils
fi

# Collect Kubernetes metrics
echo "Collecting Kubernetes metrics..."
kubectl top pods -n http-benchmark > "$RESULTS_DIR/http_k8s_metrics_${TIMESTAMP}.txt"

# Generate JSON summary
cat > "$OUTPUT_FILE" << EOF
{
  "test_type": "http",
  "timestamp": "$TIMESTAMP",
  "service_url": "$SERVICE_URL",
  "duration": $TEST_DURATION,
  "concurrent_connections": $CONCURRENT_CONNECTIONS,
  "threads": $THREADS,
  "results_files": {
    "wrk": "http_wrk_${TIMESTAMP}.txt",
    "ab": "http_ab_${TIMESTAMP}.txt",
    "k8s_metrics": "http_k8s_metrics_${TIMESTAMP}.txt"
  }
}
EOF

echo "Results saved to: $OUTPUT_FILE"
echo "=== HTTP Load Test Complete ==="
