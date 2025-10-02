#!/bin/bash
set -e

# WebSocket Load Testing Script using websocat and custom script

echo "=== WebSocket Load Test ==="

# Configuration
SERVICE_URL="${SERVICE_URL:-ws-server.websocket-benchmark.svc.cluster.local:8080}"
RESULTS_DIR="${RESULTS_DIR:-../results}"
TEST_DURATION="${TEST_DURATION:-60}"
CONCURRENT_CONNECTIONS="${CONCURRENT_CONNECTIONS:-50}"
MESSAGE_RATE="${MESSAGE_RATE:-10}"  # Messages per second per connection

# Create results directory
mkdir -p "$RESULTS_DIR"

# Get timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="$RESULTS_DIR/websocket_test_${TIMESTAMP}.json"
METRICS_FILE="$RESULTS_DIR/websocket_metrics_${TIMESTAMP}.txt"

echo "Testing WebSocket service: $SERVICE_URL"
echo "Duration: ${TEST_DURATION}s"
echo "Concurrent connections: $CONCURRENT_CONNECTIONS"
echo "Message rate: ${MESSAGE_RATE} msgs/sec per connection"

# Check if websocat is installed
if ! command -v websocat &> /dev/null; then
    echo "Installing websocat..."
    wget -qO- https://github.com/vi/websocat/releases/download/v1.12.0/websocat.x86_64-unknown-linux-musl -O /tmp/websocat
    sudo install /tmp/websocat /usr/local/bin/
    rm /tmp/websocat
fi

# Create test script for measuring connection stability and latency
cat > /tmp/ws_test_client.sh << 'WSTEST'
#!/bin/bash
SERVICE="$1"
DURATION="$2"
CONN_ID="$3"
RATE="$4"

START_TIME=$(date +%s)
END_TIME=$((START_TIME + DURATION))
MESSAGES_SENT=0
MESSAGES_RECEIVED=0
TOTAL_LATENCY=0

while [ $(date +%s) -lt $END_TIME ]; do
    SEND_TIME=$(date +%s%N)
    MESSAGE="ping:$SEND_TIME"

    # Send message and wait for echo
    RESPONSE=$(echo "$MESSAGE" | timeout 1 websocat "ws://$SERVICE" 2>/dev/null || echo "")

    if [ -n "$RESPONSE" ]; then
        RECV_TIME=$(date +%s%N)
        LATENCY=$(( (RECV_TIME - SEND_TIME) / 1000000 ))  # Convert to ms
        TOTAL_LATENCY=$((TOTAL_LATENCY + LATENCY))
        MESSAGES_RECEIVED=$((MESSAGES_RECEIVED + 1))
    fi

    MESSAGES_SENT=$((MESSAGES_SENT + 1))
    sleep $(awk "BEGIN {print 1/$RATE}")
done

# Calculate statistics
if [ $MESSAGES_RECEIVED -gt 0 ]; then
    AVG_LATENCY=$((TOTAL_LATENCY / MESSAGES_RECEIVED))
else
    AVG_LATENCY=0
fi

echo "conn_${CONN_ID}:sent=$MESSAGES_SENT,received=$MESSAGES_RECEIVED,avg_latency=${AVG_LATENCY}ms"
WSTEST

chmod +x /tmp/ws_test_client.sh

# Run concurrent connections
echo "Starting $CONCURRENT_CONNECTIONS concurrent WebSocket connections..."
PIDS=()

for i in $(seq 1 $CONCURRENT_CONNECTIONS); do
    /tmp/ws_test_client.sh "$SERVICE_URL" "$TEST_DURATION" "$i" "$MESSAGE_RATE" >> "$METRICS_FILE" 2>&1 &
    PIDS+=($!)
done

# Wait for all connections to complete
echo "Waiting for test completion..."
for pid in "${PIDS[@]}"; do
    wait $pid
done

# Collect Kubernetes metrics
echo "Collecting Kubernetes metrics..."
kubectl top pods -n websocket-benchmark > "$RESULTS_DIR/websocket_k8s_metrics_${TIMESTAMP}.txt" 2>/dev/null || echo "kubectl top not available"

# Parse results and calculate aggregated metrics
echo "Calculating aggregated metrics..."
TOTAL_SENT=0
TOTAL_RECEIVED=0
TOTAL_LATENCY=0
CONNECTION_COUNT=0

while IFS= read -r line; do
    if [[ $line =~ conn_[0-9]+:sent=([0-9]+),received=([0-9]+),avg_latency=([0-9]+)ms ]]; then
        SENT="${BASH_REMATCH[1]}"
        RECEIVED="${BASH_REMATCH[2]}"
        LATENCY="${BASH_REMATCH[3]}"

        TOTAL_SENT=$((TOTAL_SENT + SENT))
        TOTAL_RECEIVED=$((TOTAL_RECEIVED + RECEIVED))
        TOTAL_LATENCY=$((TOTAL_LATENCY + LATENCY))
        CONNECTION_COUNT=$((CONNECTION_COUNT + 1))
    fi
done < "$METRICS_FILE"

if [ $CONNECTION_COUNT -gt 0 ]; then
    AVG_LATENCY=$((TOTAL_LATENCY / CONNECTION_COUNT))
    SUCCESS_RATE=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_RECEIVED / $TOTAL_SENT) * 100}")
    THROUGHPUT=$(awk "BEGIN {printf \"%.2f\", $TOTAL_RECEIVED / $TEST_DURATION}")
else
    AVG_LATENCY=0
    SUCCESS_RATE=0
    THROUGHPUT=0
fi

# Generate JSON summary
cat > "$OUTPUT_FILE" << EOF
{
  "test_type": "websocket",
  "timestamp": "$TIMESTAMP",
  "service_url": "$SERVICE_URL",
  "duration": $TEST_DURATION,
  "concurrent_connections": $CONCURRENT_CONNECTIONS,
  "message_rate": $MESSAGE_RATE,
  "metrics": {
    "total_messages_sent": $TOTAL_SENT,
    "total_messages_received": $TOTAL_RECEIVED,
    "success_rate_percent": $SUCCESS_RATE,
    "avg_latency_ms": $AVG_LATENCY,
    "throughput_msg_per_sec": $THROUGHPUT,
    "connections_established": $CONNECTION_COUNT
  },
  "results_files": {
    "detailed_metrics": "websocket_metrics_${TIMESTAMP}.txt",
    "k8s_metrics": "websocket_k8s_metrics_${TIMESTAMP}.txt"
  }
}
EOF

echo ""
echo "=== WebSocket Test Results ==="
echo "Total messages sent: $TOTAL_SENT"
echo "Total messages received: $TOTAL_RECEIVED"
echo "Success rate: ${SUCCESS_RATE}%"
echo "Average latency: ${AVG_LATENCY}ms"
echo "Throughput: ${THROUGHPUT} messages/sec"
echo "Connections: $CONNECTION_COUNT"
echo ""
echo "Results saved to: $OUTPUT_FILE"
echo "=== WebSocket Load Test Complete ==="

# Cleanup
rm -f /tmp/ws_test_client.sh
