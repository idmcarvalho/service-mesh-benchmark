#!/bin/bash
set -e

# WebSocket Test Script
# Reads configuration from environment variables and outputs JSON results

# Configuration from environment variables
MESH_TYPE="${MESH_TYPE:-baseline}"
NAMESPACE="${NAMESPACE:-default}"
TEST_DURATION="${TEST_DURATION:-60}"
CONCURRENT_CONNECTIONS="${CONCURRENT_CONNECTIONS:-10}"
SERVICE_URL="${SERVICE_URL:-}"
RESULTS_DIR="${RESULTS_DIR:-./results}"

# Generate timestamp and output file
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${RESULTS_DIR}/${MESH_TYPE}_websocket_${TIMESTAMP}.json"

echo "========================================="
echo "WebSocket Test"
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
    echo "Example: SERVICE_URL=ws://my-service.${NAMESPACE}.svc.cluster.local/ws"
    exit 1
fi

# Check if websocat or wscat is available
WS_TOOL=""
if command -v websocat &> /dev/null; then
    WS_TOOL="websocat"
elif command -v wscat &> /dev/null; then
    WS_TOOL="wscat"
fi

if [ -z "$WS_TOOL" ]; then
    echo "WARNING: Neither websocat nor wscat is installed"
    echo "Install with:"
    echo "  websocat: cargo install websocat"
    echo "  wscat: npm install -g wscat"
    echo "Creating placeholder result..."

    # Create placeholder result
    cat > "$OUTPUT_FILE" << EOF
{
  "test_type": "websocket",
  "mesh_type": "$MESH_TYPE",
  "namespace": "$NAMESPACE",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "status": "skipped",
  "message": "WebSocket testing tool (websocat/wscat) not installed",
  "configuration": {
    "duration_seconds": $TEST_DURATION,
    "concurrent_connections": $CONCURRENT_CONNECTIONS,
    "service_url": "$SERVICE_URL"
  },
  "metrics": {
    "connections": {
      "attempted": 0,
      "successful": 0,
      "failed": 0
    },
    "messages": {
      "sent": 0,
      "received": 0
    },
    "latency": {
      "avg_ms": "N/A",
      "min_ms": "N/A",
      "max_ms": "N/A"
    }
  }
}
EOF

    echo "Placeholder result created at: $OUTPUT_FILE"
    exit 0
fi

echo "Using WebSocket tool: $WS_TOOL"
echo "Running WebSocket connection test..."

# Initialize counters
START_TIME=$(date +%s)
SUCCESSFUL_CONNECTIONS=0
FAILED_CONNECTIONS=0
MESSAGES_SENT=0
MESSAGES_RECEIVED=0

# Test WebSocket connection
echo "Testing WebSocket connectivity..."

# Simple connection test
if [ "$WS_TOOL" = "websocat" ]; then
    # Test with websocat (send ping, expect pong)
    timeout 5 echo "ping" | websocat "$SERVICE_URL" > /dev/null 2>&1 && {
        SUCCESSFUL_CONNECTIONS=1
        MESSAGES_SENT=1
        MESSAGES_RECEIVED=1
        echo "✓ WebSocket connection successful"
    } || {
        FAILED_CONNECTIONS=1
        echo "✗ WebSocket connection failed"
    }
else
    # Test with wscat
    timeout 5 wscat -c "$SERVICE_URL" --execute "ping" > /dev/null 2>&1 && {
        SUCCESSFUL_CONNECTIONS=1
        MESSAGES_SENT=1
        MESSAGES_RECEIVED=1
        echo "✓ WebSocket connection successful"
    } || {
        FAILED_CONNECTIONS=1
        echo "✗ WebSocket connection failed"
    }
fi

# Simulate load test (basic implementation)
# In production, you'd use a proper WebSocket load testing tool
echo "Running basic load test for ${TEST_DURATION}s..."

ITERATION=0
END_TIME=$((START_TIME + TEST_DURATION))
LATENCIES=()

while [ $(date +%s) -lt $END_TIME ] && [ $ITERATION -lt $CONCURRENT_CONNECTIONS ]; do
    WS_START=$(date +%s%N)

    if [ "$WS_TOOL" = "websocat" ]; then
        timeout 2 echo "test" | websocat "$SERVICE_URL" > /dev/null 2>&1 && {
            ((SUCCESSFUL_CONNECTIONS++))
            ((MESSAGES_SENT++))
            ((MESSAGES_RECEIVED++))
        } || {
            ((FAILED_CONNECTIONS++))
        }
    fi

    WS_END=$(date +%s%N)
    LATENCY_NS=$((WS_END - WS_START))
    LATENCY_MS=$((LATENCY_NS / 1000000))
    LATENCIES+=($LATENCY_MS)

    ((ITERATION++))
    sleep 1
done

# Calculate statistics
TOTAL_CONNECTIONS=$((SUCCESSFUL_CONNECTIONS + FAILED_CONNECTIONS))
AVG_LATENCY="N/A"
MIN_LATENCY="N/A"
MAX_LATENCY="N/A"

if [ ${#LATENCIES[@]} -gt 0 ]; then
    # Calculate min, max, avg
    MIN_LATENCY=${LATENCIES[0]}
    MAX_LATENCY=${LATENCIES[0]}
    SUM=0

    for latency in "${LATENCIES[@]}"; do
        SUM=$((SUM + latency))
        [ $latency -lt $MIN_LATENCY ] && MIN_LATENCY=$latency
        [ $latency -gt $MAX_LATENCY ] && MAX_LATENCY=$latency
    done

    AVG_LATENCY=$((SUM / ${#LATENCIES[@]}))
fi

# Create JSON output
cat > "$OUTPUT_FILE" << EOF
{
  "test_type": "websocket",
  "mesh_type": "$MESH_TYPE",
  "namespace": "$NAMESPACE",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "configuration": {
    "duration_seconds": $TEST_DURATION,
    "concurrent_connections": $CONCURRENT_CONNECTIONS,
    "service_url": "$SERVICE_URL",
    "tool": "$WS_TOOL"
  },
  "metrics": {
    "connections": {
      "attempted": $TOTAL_CONNECTIONS,
      "successful": $SUCCESSFUL_CONNECTIONS,
      "failed": $FAILED_CONNECTIONS,
      "success_rate_percent": $(awk "BEGIN {printf \"%.2f\", ($SUCCESSFUL_CONNECTIONS / $TOTAL_CONNECTIONS) * 100}")
    },
    "messages": {
      "sent": $MESSAGES_SENT,
      "received": $MESSAGES_RECEIVED
    },
    "latency": {
      "avg_ms": $AVG_LATENCY,
      "min_ms": $MIN_LATENCY,
      "max_ms": $MAX_LATENCY
    }
  }
}
EOF

echo "========================================="
echo "Results saved to: $OUTPUT_FILE"
echo "========================================="
echo "Summary:"
echo "  Connections Attempted: $TOTAL_CONNECTIONS"
echo "  Successful: $SUCCESSFUL_CONNECTIONS"
echo "  Failed: $FAILED_CONNECTIONS"
echo "  Messages Sent: $MESSAGES_SENT"
echo "  Messages Received: $MESSAGES_RECEIVED"
echo "  Avg Latency: ${AVG_LATENCY}ms"
echo "========================================="

exit 0
