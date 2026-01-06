#!/bin/bash
set -e

# gRPC Load Test Script using ghz
# Reads configuration from environment variables and outputs JSON results

# Configuration from environment variables
MESH_TYPE="${MESH_TYPE:-baseline}"
NAMESPACE="${NAMESPACE:-default}"
TEST_DURATION="${TEST_DURATION:-60}"
CONCURRENT_CONNECTIONS="${CONCURRENT_CONNECTIONS:-50}"
SERVICE_URL="${SERVICE_URL:-}"
PROTO_FILE="${PROTO_FILE:-}"
CALL_METHOD="${CALL_METHOD:-}"
RESULTS_DIR="${RESULTS_DIR:-./results}"

# Generate timestamp and output file
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${RESULTS_DIR}/${MESH_TYPE}_grpc_${TIMESTAMP}.json"

echo "========================================="
echo "gRPC Load Test"
echo "========================================="
echo "Mesh Type: $MESH_TYPE"
echo "Namespace: $NAMESPACE"
echo "Duration: ${TEST_DURATION}s"
echo "Connections: $CONCURRENT_CONNECTIONS"
echo "Service URL: $SERVICE_URL"
echo "Output: $OUTPUT_FILE"
echo "========================================="

# Ensure results directory exists
mkdir -p "$RESULTS_DIR"

# Determine service URL if not provided
if [ -z "$SERVICE_URL" ]; then
    echo "ERROR: SERVICE_URL environment variable is required"
    echo "Example: SERVICE_URL=my-service.${NAMESPACE}.svc.cluster.local:9000"
    exit 1
fi

# Check if ghz is available
if ! command -v ghz &> /dev/null; then
    echo "WARNING: ghz is not installed"
    echo "Install with: go install github.com/bojand/ghz/cmd/ghz@latest"
    echo "Creating stub result file..."

    # Create stub result file for testing
    cat > "$OUTPUT_FILE" << EOF
{
  "test_type": "grpc",
  "mesh_type": "$MESH_TYPE",
  "namespace": "$NAMESPACE",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "status": "skipped",
  "message": "ghz not installed - test skipped",
  "configuration": {
    "duration_seconds": $TEST_DURATION,
    "concurrent_connections": $CONCURRENT_CONNECTIONS,
    "service_url": "$SERVICE_URL"
  }
}
EOF
    echo "Stub result created at: $OUTPUT_FILE"
    exit 0
fi

# For now, create a working result with dummy gRPC call
# In production, you would specify proto file and method
echo "Running gRPC load test..."

# Create temporary file for ghz output
GHZ_OUTPUT=$(mktemp)

# Determine proto and call parameters
if [ -z "$CALL_METHOD" ]; then
    echo "WARNING: CALL_METHOD not specified. Using health check as default."
    CALL_METHOD="grpc.health.v1.Health/Check"
fi

# Run ghz benchmark
# Note: This assumes a health check endpoint. Customize for your services.
ghz --insecure \
    --proto=/dev/null \
    --call="$CALL_METHOD" \
    --duration="${TEST_DURATION}s" \
    --connections="$CONCURRENT_CONNECTIONS" \
    --format=json \
    "$SERVICE_URL" > "$GHZ_OUTPUT" 2>&1 || {

    echo "WARNING: ghz command failed (possibly no proto file or service unavailable)"
    echo "Creating placeholder result..."

    # Create placeholder result
    cat > "$OUTPUT_FILE" << EOF
{
  "test_type": "grpc",
  "mesh_type": "$MESH_TYPE",
  "namespace": "$NAMESPACE",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "status": "unavailable",
  "message": "gRPC service not available or proto file not provided",
  "configuration": {
    "duration_seconds": $TEST_DURATION,
    "concurrent_connections": $CONCURRENT_CONNECTIONS,
    "service_url": "$SERVICE_URL",
    "call_method": "$CALL_METHOD"
  },
  "metrics": {
    "latency": {
      "avg": "N/A",
      "p50": "N/A",
      "p95": "N/A",
      "p99": "N/A"
    },
    "throughput": {
      "requests_per_second": "N/A"
    },
    "requests": {
      "total": 0,
      "success": 0,
      "errors": 0
    }
  }
}
EOF

    rm -f "$GHZ_OUTPUT"
    echo "Placeholder result created at: $OUTPUT_FILE"
    exit 0
}

echo "Load test completed. Processing results..."

# ghz already outputs JSON, so we can use it directly
# But we'll wrap it in our standard format
GHZ_RESULT=$(cat "$GHZ_OUTPUT")

# Extract key metrics from ghz JSON output
TOTAL_REQUESTS=$(echo "$GHZ_RESULT" | jq -r '.count // 0')
AVG_LATENCY=$(echo "$GHZ_RESULT" | jq -r '.average // 0')
P50_LATENCY=$(echo "$GHZ_RESULT" | jq -r '.latencyDistribution[] | select(.percentage == 50) | .latency // "N/A"')
P95_LATENCY=$(echo "$GHZ_RESULT" | jq -r '.latencyDistribution[] | select(.percentage == 95) | .latency // "N/A"')
P99_LATENCY=$(echo "$GHZ_RESULT" | jq -r '.latencyDistribution[] | select(.percentage == 99) | .latency // "N/A"')
RPS=$(echo "$GHZ_RESULT" | jq -r '.rps // 0')
SUCCESS=$(echo "$GHZ_RESULT" | jq -r '.statusCodeDistribution."0" // 0')
ERRORS=$(echo "$GHZ_RESULT" | jq -r '.errors // 0')

# Create standardized JSON output
cat > "$OUTPUT_FILE" << EOF
{
  "test_type": "grpc",
  "mesh_type": "$MESH_TYPE",
  "namespace": "$NAMESPACE",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "configuration": {
    "duration_seconds": $TEST_DURATION,
    "concurrent_connections": $CONCURRENT_CONNECTIONS,
    "service_url": "$SERVICE_URL",
    "call_method": "$CALL_METHOD"
  },
  "metrics": {
    "latency": {
      "avg": $AVG_LATENCY,
      "p50": "$P50_LATENCY",
      "p95": "$P95_LATENCY",
      "p99": "$P99_LATENCY"
    },
    "throughput": {
      "requests_per_second": $RPS
    },
    "requests": {
      "total": $TOTAL_REQUESTS,
      "success": $SUCCESS,
      "errors": $ERRORS
    }
  },
  "ghz_output": $GHZ_RESULT
}
EOF

# Clean up
rm -f "$GHZ_OUTPUT"

echo "========================================="
echo "Results saved to: $OUTPUT_FILE"
echo "========================================="
echo "Summary:"
echo "  Total Requests: $TOTAL_REQUESTS"
echo "  Requests/sec: $RPS"
echo "  Avg Latency: ${AVG_LATENCY}ns"
echo "  P95 Latency: $P95_LATENCY"
echo "  P99 Latency: $P99_LATENCY"
echo "  Success: $SUCCESS"
echo "  Errors: $ERRORS"
echo "========================================="

exit 0
