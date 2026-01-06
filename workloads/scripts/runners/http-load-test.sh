#!/bin/bash
set -e

# HTTP Load Test Script using wrk
# Reads configuration from environment variables and outputs JSON results

# Configuration from environment variables
MESH_TYPE="${MESH_TYPE:-baseline}"
NAMESPACE="${NAMESPACE:-default}"
TEST_DURATION="${TEST_DURATION:-60}"
CONCURRENT_CONNECTIONS="${CONCURRENT_CONNECTIONS:-100}"
THREADS="${THREADS:-4}"
SERVICE_URL="${SERVICE_URL:-}"
RESULTS_DIR="${RESULTS_DIR:-./results}"

# Generate timestamp and output file
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${RESULTS_DIR}/${MESH_TYPE}_http_${TIMESTAMP}.json"

echo "========================================="
echo "HTTP Load Test"
echo "========================================="
echo "Mesh Type: $MESH_TYPE"
echo "Namespace: $NAMESPACE"
echo "Duration: ${TEST_DURATION}s"
echo "Connections: $CONCURRENT_CONNECTIONS"
echo "Threads: $THREADS"
echo "Service URL: $SERVICE_URL"
echo "Output: $OUTPUT_FILE"
echo "========================================="

# Ensure results directory exists
mkdir -p "$RESULTS_DIR"

# Determine service URL if not provided
if [ -z "$SERVICE_URL" ]; then
    echo "ERROR: SERVICE_URL environment variable is required"
    echo "Example: SERVICE_URL=http://my-service.${NAMESPACE}.svc.cluster.local"
    exit 1
fi

# Check if wrk is available
if ! command -v wrk &> /dev/null; then
    echo "ERROR: wrk is not installed"
    echo "Install with: sudo apt-get install wrk"
    exit 1
fi

# Run wrk benchmark
echo "Starting HTTP load test..."
echo "Target: $SERVICE_URL"

# Create a temporary file for wrk output
WRK_OUTPUT=$(mktemp)

# Run wrk and capture output
wrk -t"$THREADS" \
    -c"$CONCURRENT_CONNECTIONS" \
    -d"${TEST_DURATION}s" \
    --latency \
    "$SERVICE_URL" > "$WRK_OUTPUT" 2>&1

# Check if wrk succeeded
if [ $? -ne 0 ]; then
    echo "ERROR: wrk command failed"
    cat "$WRK_OUTPUT"
    rm -f "$WRK_OUTPUT"
    exit 1
fi

echo "Load test completed. Processing results..."

# Parse wrk output and convert to JSON
# This is a simplified parser - wrk output format:
# Latency: avg, stdev, max, +/- stdev
# Req/Sec: avg, stdev, max, +/- stdev
# Total requests, duration, data transferred

# Extract key metrics using awk and grep
LATENCY_AVG=$(grep "Latency" "$WRK_OUTPUT" | awk '{print $2}')
LATENCY_STDEV=$(grep "Latency" "$WRK_OUTPUT" | awk '{print $3}')
LATENCY_MAX=$(grep "Latency" "$WRK_OUTPUT" | awk '{print $4}')

REQ_SEC=$(grep "Req/Sec" "$WRK_OUTPUT" | awk '{print $2}')
TOTAL_REQUESTS=$(grep "requests in" "$WRK_OUTPUT" | awk '{print $1}')
TOTAL_DURATION=$(grep "requests in" "$WRK_OUTPUT" | awk '{print $3}')
ERRORS=$(grep -c "Socket errors" "$WRK_OUTPUT" || echo "0")

# Calculate error rate
if [ "$TOTAL_REQUESTS" -gt 0 ]; then
    ERROR_RATE=$(awk "BEGIN {printf \"%.2f\", ($ERRORS / $TOTAL_REQUESTS) * 100}")
else
    ERROR_RATE="0.00"
fi

# Parse percentile latency if available
LATENCY_P50=$(grep "50.000%" "$WRK_OUTPUT" | awk '{print $2}' || echo "N/A")
LATENCY_P75=$(grep "75.000%" "$WRK_OUTPUT" | awk '{print $2}' || echo "N/A")
LATENCY_P90=$(grep "90.000%" "$WRK_OUTPUT" | awk '{print $2}' || echo "N/A")
LATENCY_P99=$(grep "99.000%" "$WRK_OUTPUT" | awk '{print $2}' || echo "N/A")

# Get current timestamp
CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Create JSON output
cat > "$OUTPUT_FILE" << EOF
{
  "test_type": "http",
  "mesh_type": "$MESH_TYPE",
  "namespace": "$NAMESPACE",
  "timestamp": "$CURRENT_TIME",
  "configuration": {
    "duration_seconds": $TEST_DURATION,
    "concurrent_connections": $CONCURRENT_CONNECTIONS,
    "threads": $THREADS,
    "service_url": "$SERVICE_URL"
  },
  "metrics": {
    "latency": {
      "avg": "$LATENCY_AVG",
      "stdev": "$LATENCY_STDEV",
      "max": "$LATENCY_MAX",
      "p50": "$LATENCY_P50",
      "p75": "$LATENCY_P75",
      "p90": "$LATENCY_P90",
      "p99": "$LATENCY_P99"
    },
    "throughput": {
      "requests_per_second": "$REQ_SEC"
    },
    "requests": {
      "total": $TOTAL_REQUESTS,
      "errors": $ERRORS,
      "error_rate_percent": $ERROR_RATE
    },
    "duration": "$TOTAL_DURATION"
  },
  "raw_output": $(cat "$WRK_OUTPUT" | jq -Rs .)
}
EOF

# Clean up
rm -f "$WRK_OUTPUT"

echo "========================================="
echo "Results saved to: $OUTPUT_FILE"
echo "========================================="
echo "Summary:"
echo "  Total Requests: $TOTAL_REQUESTS"
echo "  Requests/sec: $REQ_SEC"
echo "  Avg Latency: $LATENCY_AVG"
echo "  Max Latency: $LATENCY_MAX"
echo "  Error Rate: ${ERROR_RATE}%"
echo "========================================="

exit 0
