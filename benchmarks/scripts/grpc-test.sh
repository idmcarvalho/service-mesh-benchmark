#!/bin/bash
# shellcheck shell=bash
set -euo pipefail

# gRPC Load Testing Script using ghz

echo "=== gRPC Load Test ==="

# Configuration
SERVICE_URL="${SERVICE_URL:-grpc-server.grpc-benchmark.svc.cluster.local:9000}"
NAMESPACE="${NAMESPACE:-grpc-benchmark}"
RESULTS_DIR="${RESULTS_DIR:-../results}"
TEST_DURATION="${TEST_DURATION:-60s}"
CONCURRENT_CONNECTIONS="${CONCURRENT_CONNECTIONS:-50}"
TOTAL_REQUESTS="${TOTAL_REQUESTS:-10000}"
WARMUP_DURATION="${WARMUP_DURATION:-10}"
COOLDOWN_DURATION="${COOLDOWN_DURATION:-5}"
MESH_TYPE="${MESH_TYPE:-baseline}"

# SECURITY: TLS configuration
# Set ALLOW_INSECURE_GRPC=true ONLY in isolated test environments
# For production, always use proper TLS certificates
ALLOW_INSECURE_GRPC="${ALLOW_INSECURE_GRPC:-false}"

# Validate inputs
if [[ ! "${NAMESPACE}" =~ ^[a-z0-9-]+$ ]]; then
    echo "Error: Invalid namespace format" >&2
    exit 1
fi

# Create results directory
mkdir -p "${RESULTS_DIR}"

# Get timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${RESULTS_DIR}/grpc_test_${TIMESTAMP}.json"

echo "Testing gRPC service: ${SERVICE_URL}"
echo "Namespace: ${NAMESPACE}"
echo "Mesh Type: ${MESH_TYPE}"
echo "Duration: ${TEST_DURATION}"
echo "Concurrent connections: ${CONCURRENT_CONNECTIONS}"
echo "Total requests: ${TOTAL_REQUESTS}"
echo "Warm-up: ${WARMUP_DURATION}s, Cool-down: ${COOLDOWN_DURATION}s"
echo ""

# Health check - wait for pods to be ready
echo "Checking pod readiness..."
if ! kubectl wait --for=condition=ready pod -l app=grpc-server -n "${NAMESPACE}" --timeout=300s 2>/dev/null; then
    echo "Warning: Pods may not be ready, but continuing anyway..."
fi

# Verify service is accessible
echo "Verifying gRPC service connectivity..."
if ! kubectl run test-grpcurl --image=fullstorydev/grpcurl:latest --rm -i --restart=Never -n "$NAMESPACE" -- -plaintext "$SERVICE_URL" list &> /dev/null; then
    echo "Warning: Could not verify gRPC service accessibility"
fi
echo "Service check complete"
echo ""

# Warm-up period
echo "Running warm-up period (${WARMUP_DURATION}s)..."
sleep "$WARMUP_DURATION"
echo "Warm-up complete"
echo ""

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

# SECURITY CHECK: Warn if using insecure mode
if [[ "${ALLOW_INSECURE_GRPC}" == "true" ]]; then
    echo "⚠️  WARNING: Running gRPC tests in INSECURE mode (TLS disabled)" >&2
    echo "⚠️  This should ONLY be used in isolated test environments" >&2
    echo "⚠️  For production, configure proper TLS certificates" >&2

    ghz --insecure \
        --proto=/dev/null \
        --call=grpc.health.v1.Health/Check \
        --duration="${TEST_DURATION}" \
        --connections="${CONCURRENT_CONNECTIONS}" \
        --concurrency="${CONCURRENT_CONNECTIONS}" \
        --format=json \
        --output="${OUTPUT_FILE}" \
        "${SERVICE_URL}" || echo "ghz test completed with errors (expected if service doesn't implement health check)"
else
    # Secure mode: use TLS (requires certificates)
    echo "Running in SECURE mode with TLS verification"

    # Check if TLS certificates are available
    if [[ -f "${GRPC_CA_CERT:-}" ]] && [[ -f "${GRPC_CLIENT_CERT:-}" ]] && [[ -f "${GRPC_CLIENT_KEY:-}" ]]; then
        ghz \
            --cacert="${GRPC_CA_CERT}" \
            --cert="${GRPC_CLIENT_CERT}" \
            --key="${GRPC_CLIENT_KEY}" \
            --proto=/dev/null \
            --call=grpc.health.v1.Health/Check \
            --duration="${TEST_DURATION}" \
            --connections="${CONCURRENT_CONNECTIONS}" \
            --concurrency="${CONCURRENT_CONNECTIONS}" \
            --format=json \
            --output="${OUTPUT_FILE}" \
            "${SERVICE_URL}" || echo "ghz test completed with errors"
    else
        echo "ERROR: TLS certificates not found!" >&2
        echo "Either set ALLOW_INSECURE_GRPC=true for test environments," >&2
        echo "or provide certificates via:" >&2
        echo "  GRPC_CA_CERT=/path/to/ca.crt" >&2
        echo "  GRPC_CLIENT_CERT=/path/to/client.crt" >&2
        echo "  GRPC_CLIENT_KEY=/path/to/client.key" >&2
        exit 1
    fi
fi

# Fallback: use grpcurl for basic testing
echo "Running grpcurl tests..."
grpcurl -plaintext "$SERVICE_URL" list > "$RESULTS_DIR/grpc_services_${TIMESTAMP}.txt" 2>/dev/null || echo "grpcurl list failed"

# Cool-down period
echo ""
echo "Running cool-down period (${COOLDOWN_DURATION}s)..."
sleep "$COOLDOWN_DURATION"
echo "Cool-down complete"
echo ""

# Collect Kubernetes metrics
echo "Collecting Kubernetes metrics..."
kubectl top pods -n "$NAMESPACE" > "$RESULTS_DIR/grpc_k8s_metrics_${TIMESTAMP}.txt" 2>/dev/null || echo "kubectl top not available"

# Add mesh_type to output JSON if ghz succeeded
if [ -f "$OUTPUT_FILE" ]; then
    # Create temp file with mesh_type added
    jq ". + {\"mesh_type\": \"$MESH_TYPE\", \"namespace\": \"$NAMESPACE\"}" "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
fi

echo ""
echo "Results saved to: $OUTPUT_FILE"
echo "=== gRPC Load Test Complete ==="
