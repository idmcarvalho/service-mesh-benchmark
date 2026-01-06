#!/bin/bash
set -e

# ML Workload Test Script
# Tests ML inference endpoints with real HTTP requests
# Reads configuration from environment variables and outputs JSON results

# Configuration from environment variables
MESH_TYPE="${MESH_TYPE:-baseline}"
NAMESPACE="${NAMESPACE:-default}"
TEST_DURATION="${TEST_DURATION:-60}"
CONCURRENT_CONNECTIONS="${CONCURRENT_CONNECTIONS:-5}"
SERVICE_URL="${SERVICE_URL:-}"
REQUEST_PAYLOAD="${REQUEST_PAYLOAD:-}"
RESULTS_DIR="${RESULTS_DIR:-./results}"

# Generate timestamp and output file
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${RESULTS_DIR}/${MESH_TYPE}_ml_${TIMESTAMP}.json"

echo "========================================="
echo "ML Workload Test"
echo "========================================="
echo "Mesh Type: $MESH_TYPE"
echo "Namespace: $NAMESPACE"
echo "Duration: ${TEST_DURATION}s"
echo "Concurrent Connections: $CONCURRENT_CONNECTIONS"
echo "Service URL: $SERVICE_URL"
echo "Output: $OUTPUT_FILE"
echo "========================================="

# Ensure results directory exists
mkdir -p "$RESULTS_DIR"

# Validate service URL
if [ -z "$SERVICE_URL" ]; then
    echo "ERROR: SERVICE_URL environment variable is required"
    echo ""
    echo "Example ML service URLs:"
    echo "  - TensorFlow Serving: http://tensorflow-serving.${NAMESPACE}.svc.cluster.local:8501/v1/models/model:predict"
    echo "  - PyTorch Serve: http://pytorch-serve.${NAMESPACE}.svc.cluster.local:8080/predictions/model"
    echo "  - Custom ML API: http://ml-service.${NAMESPACE}.svc.cluster.local/predict"
    echo ""
    echo "You must deploy an ML inference service first."
    exit 1
fi

# Default payload for ML inference (minimal example)
if [ -z "$REQUEST_PAYLOAD" ]; then
    REQUEST_PAYLOAD='{"instances": [[1.0, 2.0, 3.0, 4.0]]}'
    echo "Using default payload: $REQUEST_PAYLOAD"
fi

# Check if required tools are available
if ! command -v curl &> /dev/null; then
    echo "ERROR: curl is not installed"
    exit 1
fi

# Verify ML service is accessible
echo "Verifying ML service accessibility..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$SERVICE_URL" \
    -H "Content-Type: application/json" \
    -d "$REQUEST_PAYLOAD" \
    --max-time 10 2>/dev/null || echo "000")

if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
    echo "WARNING: ML service returned HTTP $HTTP_CODE or is not accessible"
    echo "Service URL: $SERVICE_URL"
    echo "This test will measure the failure behavior."
fi

echo "Running ML inference load test..."

# Use Apache Bench (ab) if available, otherwise use curl loop
if command -v ab &> /dev/null; then
    echo "Using Apache Bench (ab) for load testing..."

    # Create temporary file for request payload
    PAYLOAD_FILE=$(mktemp)
    echo "$REQUEST_PAYLOAD" > "$PAYLOAD_FILE"

    # Run ab benchmark
    AB_OUTPUT=$(mktemp)

    ab -n $((TEST_DURATION * CONCURRENT_CONNECTIONS)) \
       -c "$CONCURRENT_CONNECTIONS" \
       -t "$TEST_DURATION" \
       -p "$PAYLOAD_FILE" \
       -T "application/json" \
       "$SERVICE_URL" > "$AB_OUTPUT" 2>&1 || {
        echo "WARNING: ab command encountered errors"
    }

    # Parse ab output
    TOTAL_REQUESTS=$(grep "Complete requests:" "$AB_OUTPUT" | awk '{print $3}')
    FAILED_REQUESTS=$(grep "Failed requests:" "$AB_OUTPUT" | awk '{print $3}')
    REQUESTS_PER_SEC=$(grep "Requests per second:" "$AB_OUTPUT" | awk '{print $4}')
    TIME_PER_REQUEST=$(grep "Time per request:" "$AB_OUTPUT" | head -1 | awk '{print $4}')

    # Extract percentile latencies
    LATENCY_50=$(grep "50%" "$AB_OUTPUT" | awk '{print $2}')
    LATENCY_75=$(grep "75%" "$AB_OUTPUT" | awk '{print $2}')
    LATENCY_90=$(grep "90%" "$AB_OUTPUT" | awk '{print $2}')
    LATENCY_95=$(grep "95%" "$AB_OUTPUT" | awk '{print $2}')
    LATENCY_99=$(grep "99%" "$AB_OUTPUT" | awk '{print $2}')

    SUCCESSFUL_REQUESTS=$((TOTAL_REQUESTS - FAILED_REQUESTS))

    # Cleanup
    rm -f "$PAYLOAD_FILE" "$AB_OUTPUT"

else
    echo "Apache Bench not available, using curl-based testing..."
    echo "Note: Install 'ab' (apache2-utils) for better performance testing"

    # Fallback to curl loop
    START_TIME=$(date +%s)
    END_TIME=$((START_TIME + TEST_DURATION))
    TOTAL_REQUESTS=0
    SUCCESSFUL_REQUESTS=0
    FAILED_REQUESTS=0
    TOTAL_TIME_MS=0
    LATENCIES=()

    while [ $(date +%s) -lt $END_TIME ]; do
        # Run concurrent requests
        for ((i=0; i<CONCURRENT_CONNECTIONS; i++)); do
            REQ_START=$(date +%s%N)

            HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
                -X POST "$SERVICE_URL" \
                -H "Content-Type: application/json" \
                -d "$REQUEST_PAYLOAD" \
                --max-time 30 2>/dev/null || echo "000")

            REQ_END=$(date +%s%N)
            LATENCY_NS=$((REQ_END - REQ_START))
            LATENCY_MS=$((LATENCY_NS / 1000000))

            ((TOTAL_REQUESTS++))

            if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
                ((SUCCESSFUL_REQUESTS++))
                LATENCIES+=($LATENCY_MS)
                TOTAL_TIME_MS=$((TOTAL_TIME_MS + LATENCY_MS))
            else
                ((FAILED_REQUESTS++))
            fi
        done

        sleep 0.1  # Small delay between batches
    done

    # Calculate metrics
    ACTUAL_DURATION=$(($(date +%s) - START_TIME))
    REQUESTS_PER_SEC=$(awk "BEGIN {printf \"%.2f\", $TOTAL_REQUESTS / $ACTUAL_DURATION}")
    TIME_PER_REQUEST=$(awk "BEGIN {printf \"%.2f\", $TOTAL_TIME_MS / $SUCCESSFUL_REQUESTS}")

    # Calculate percentiles (simplified)
    if [ ${#LATENCIES[@]} -gt 0 ]; then
        IFS=$'\n' SORTED_LATENCIES=($(sort -n <<<"${LATENCIES[*]}"))
        COUNT=${#SORTED_LATENCIES[@]}
        LATENCY_50=${SORTED_LATENCIES[$((COUNT * 50 / 100))]}
        LATENCY_75=${SORTED_LATENCIES[$((COUNT * 75 / 100))]}
        LATENCY_90=${SORTED_LATENCIES[$((COUNT * 90 / 100))]}
        LATENCY_95=${SORTED_LATENCIES[$((COUNT * 95 / 100))]}
        LATENCY_99=${SORTED_LATENCIES[$((COUNT * 99 / 100))]}
    else
        LATENCY_50=0
        LATENCY_75=0
        LATENCY_90=0
        LATENCY_95=0
        LATENCY_99=0
    fi
fi

# Calculate success rate
if [ $TOTAL_REQUESTS -gt 0 ]; then
    SUCCESS_RATE=$(awk "BEGIN {printf \"%.2f\", ($SUCCESSFUL_REQUESTS / $TOTAL_REQUESTS) * 100}")
else
    SUCCESS_RATE="0.00"
fi

# Create JSON output
cat > "$OUTPUT_FILE" << EOF
{
  "test_type": "ml",
  "mesh_type": "$MESH_TYPE",
  "namespace": "$NAMESPACE",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "configuration": {
    "duration_seconds": $TEST_DURATION,
    "concurrent_connections": $CONCURRENT_CONNECTIONS,
    "service_url": "$SERVICE_URL"
  },
  "metrics": {
    "requests": {
      "total": ${TOTAL_REQUESTS:-0},
      "successful": ${SUCCESSFUL_REQUESTS:-0},
      "failed": ${FAILED_REQUESTS:-0},
      "success_rate_percent": $SUCCESS_RATE
    },
    "throughput": {
      "requests_per_second": ${REQUESTS_PER_SEC:-0}
    },
    "latency": {
      "avg_ms": ${TIME_PER_REQUEST:-0},
      "p50_ms": ${LATENCY_50:-0},
      "p75_ms": ${LATENCY_75:-0},
      "p90_ms": ${LATENCY_90:-0},
      "p95_ms": ${LATENCY_95:-0},
      "p99_ms": ${LATENCY_99:-0}
    }
  },
  "notes": "ML inference endpoint load test results"
}
EOF

echo "========================================="
echo "Results saved to: $OUTPUT_FILE"
echo "========================================="
echo "Summary:"
echo "  Total Requests: ${TOTAL_REQUESTS:-0}"
echo "  Successful: ${SUCCESSFUL_REQUESTS:-0}"
echo "  Failed: ${FAILED_REQUESTS:-0}"
echo "  Success Rate: ${SUCCESS_RATE}%"
echo "  Throughput: ${REQUESTS_PER_SEC:-0} req/sec"
echo "  Avg Latency: ${TIME_PER_REQUEST:-0}ms"
echo "  P95 Latency: ${LATENCY_95:-0}ms"
echo "  P99 Latency: ${LATENCY_99:-0}ms"
echo "========================================="

exit 0
