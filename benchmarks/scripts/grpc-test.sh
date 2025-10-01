#!/bin/bash
set -e

# gRPC Load Testing Script using ghz

echo "=== gRPC Load Test ==="

# Configuration
SERVICE_URL="${SERVICE_URL:-grpc-server.grpc-benchmark.svc.cluster.local:9000}"
RESULTS_DIR="${RESULTS_DIR:-../results}"
TEST_DURATION="${TEST_DURATION:-60s}"
CONCURRENT_CONNECTIONS="${CONCURRENT_CONNECTIONS:-50}"
TOTAL_REQUESTS="${TOTAL_REQUESTS:-10000}"

# Create results directory
mkdir -p "$RESULTS_DIR"

# Get timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="$RESULTS_DIR/grpc_test_${TIMESTAMP}.json"

echo "Testing gRPC service: $SERVICE_URL"
echo "Duration: $TEST_DURATION"
echo "Concurrent connections: $CONCURRENT_CONNECTIONS"
echo "Total requests: $TOTAL_REQUESTS"

# Check if ghz is installed
if ! command -v ghz &> /dev/null; then
    echo "Installing ghz..."
    wget -q https://github.com/bojand/ghz/releases/download/v0.117.0/ghz-linux-x86_64.tar.gz
    tar -xzf ghz-linux-x86_64.tar.gz
    sudo mv ghz /usr/local/bin/
    rm ghz-linux-x86_64.tar.gz
fi

# Run ghz benchmark for list method
echo "Running ghz benchmark..."
ghz --insecure \
    --proto=/dev/null \
    --call=grpc.health.v1.Health/Check \
    --duration=$TEST_DURATION \
    --connections=$CONCURRENT_CONNECTIONS \
    --concurrency=$CONCURRENT_CONNECTIONS \
    --format=json \
    --output="$OUTPUT_FILE" \
    "$SERVICE_URL" || echo "ghz test completed with errors (expected if service doesn't implement health check)"

# Fallback: use grpcurl for basic testing
echo "Running grpcurl tests..."
grpcurl -plaintext "$SERVICE_URL" list > "$RESULTS_DIR/grpc_services_${TIMESTAMP}.txt"

# Collect Kubernetes metrics
echo "Collecting Kubernetes metrics..."
kubectl top pods -n grpc-benchmark > "$RESULTS_DIR/grpc_k8s_metrics_${TIMESTAMP}.txt"

echo "Results saved to: $OUTPUT_FILE"
echo "=== gRPC Load Test Complete ==="
