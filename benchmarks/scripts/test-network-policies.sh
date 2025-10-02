#!/bin/bash
set -e

# Network Policy Performance Testing Script
# Tests eBPF-based network policy enforcement overhead

echo "=== Network Policy Performance Test ==="

# Configuration
RESULTS_DIR="${RESULTS_DIR:-../results}"
TEST_DURATION="${TEST_DURATION:-30}"
NAMESPACE="${NAMESPACE:-policy-test}"
MESH_TYPE="${MESH_TYPE:-cilium}"

# Create results directory
mkdir -p "$RESULTS_DIR/network-policies"

# Get timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="$RESULTS_DIR/network-policies/policy_test_${TIMESTAMP}.json"

echo "Test duration: ${TEST_DURATION}s"
echo "Namespace: $NAMESPACE"
echo "Mesh type: $MESH_TYPE"
echo ""

# Create test namespace
echo "Creating test namespace..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Deploy test workloads
echo "Deploying test workloads..."
cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: $NAMESPACE
spec:
  selector:
    app: backend
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: $NAMESPACE
spec:
  replicas: 3
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: client-allowed
  namespace: $NAMESPACE
spec:
  replicas: 2
  selector:
    matchLabels:
      app: client-allowed
  template:
    metadata:
      labels:
        app: client-allowed
        role: allowed
    spec:
      containers:
      - name: curl
        image: curlimages/curl:latest
        command: ["/bin/sh", "-c"]
        args:
          - |
            while true; do
              curl -s http://backend/ > /dev/null || true
              sleep 0.1
            done
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: client-denied
  namespace: $NAMESPACE
spec:
  replicas: 2
  selector:
    matchLabels:
      app: client-denied
  template:
    metadata:
      labels:
        app: client-denied
        role: denied
    spec:
      containers:
      - name: curl
        image: curlimages/curl:latest
        command: ["/bin/sh", "-c"]
        args:
          - |
            while true; do
              curl -s --max-time 2 http://backend/ > /dev/null || true
              sleep 0.1
            done
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
EOF

# Wait for pods to be ready
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=backend -n "$NAMESPACE" --timeout=120s
kubectl wait --for=condition=ready pod -l app=client-allowed -n "$NAMESPACE" --timeout=120s
kubectl wait --for=condition=ready pod -l app=client-denied -n "$NAMESPACE" --timeout=120s

echo "Pods are ready"
echo ""

# Test 1: Baseline (no network policy)
echo "Test 1: Baseline performance (no network policy)"
echo "Running baseline test for ${TEST_DURATION}s..."
sleep "$TEST_DURATION"

# Collect baseline metrics
BASELINE_ALLOWED_REQUESTS=$(kubectl logs -n "$NAMESPACE" -l app=client-allowed --tail=100 2>/dev/null | grep -c "200" || echo "0")
BASELINE_DENIED_REQUESTS=$(kubectl logs -n "$NAMESPACE" -l app=client-denied --tail=100 2>/dev/null | grep -c "200" || echo "0")

echo "Baseline - Allowed client requests: $BASELINE_ALLOWED_REQUESTS"
echo "Baseline - Denied client requests: $BASELINE_DENIED_REQUESTS"
echo ""

# Apply network policy
echo "Test 2: With L3/L4 network policy"
echo "Applying Cilium network policy..."

if [ "$MESH_TYPE" = "cilium" ]; then
    # Use CiliumNetworkPolicy for eBPF enforcement
    cat <<EOF | kubectl apply -f -
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: backend-policy
  namespace: $NAMESPACE
spec:
  endpointSelector:
    matchLabels:
      app: backend
  ingress:
  - fromEndpoints:
    - matchLabels:
        role: allowed
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
EOF
else
    # Fallback to standard NetworkPolicy
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-policy
  namespace: $NAMESPACE
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: allowed
    ports:
    - protocol: TCP
      port: 80
EOF
fi

# Wait for policy to be enforced
echo "Waiting for policy enforcement..."
sleep 10

echo "Running test with policy for ${TEST_DURATION}s..."
sleep "$TEST_DURATION"

# Collect policy-enforced metrics
POLICY_ALLOWED_REQUESTS=$(kubectl logs -n "$NAMESPACE" -l app=client-allowed --tail=100 2>/dev/null | grep -c "200" || echo "0")
POLICY_DENIED_REQUESTS=$(kubectl logs -n "$NAMESPACE" -l app=client-denied --tail=100 2>/dev/null | grep -c "200" || echo "0")

echo "With policy - Allowed client successful requests: $POLICY_ALLOWED_REQUESTS"
echo "With policy - Denied client successful requests: $POLICY_DENIED_REQUESTS"
echo ""

# Test 3: L7 HTTP policy (Cilium only)
if [ "$MESH_TYPE" = "cilium" ]; then
    echo "Test 3: With L7 HTTP policy"
    echo "Applying L7 Cilium network policy..."

    cat <<EOF | kubectl apply -f -
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: backend-l7-policy
  namespace: $NAMESPACE
spec:
  endpointSelector:
    matchLabels:
      app: backend
  ingress:
  - fromEndpoints:
    - matchLabels:
        role: allowed
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
      rules:
        http:
        - method: "GET"
          path: "/"
EOF

    # Wait for L7 policy enforcement
    echo "Waiting for L7 policy enforcement..."
    sleep 10

    echo "Running L7 test for ${TEST_DURATION}s..."
    sleep "$TEST_DURATION"

    L7_ALLOWED_REQUESTS=$(kubectl logs -n "$NAMESPACE" -l app=client-allowed --tail=100 2>/dev/null | grep -c "200" || echo "0")
    L7_DENIED_REQUESTS=$(kubectl logs -n "$NAMESPACE" -l app=client-denied --tail=100 2>/dev/null | grep -c "200" || echo "0")

    echo "With L7 policy - Allowed client requests: $L7_ALLOWED_REQUESTS"
    echo "With L7 policy - Denied client requests: $L7_DENIED_REQUESTS"
else
    L7_ALLOWED_REQUESTS=0
    L7_DENIED_REQUESTS=0
fi
echo ""

# Collect eBPF metrics (Cilium only)
POLICY_DROPS=0
POLICY_ALLOWS=0
EBPF_OVERHEAD_CPU=0
EBPF_OVERHEAD_MEMORY=0

if [ "$MESH_TYPE" = "cilium" ]; then
    echo "Collecting eBPF policy enforcement metrics..."
    CILIUM_POD=$(kubectl get pod -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')

    # Get policy enforcement stats
    POLICY_STATS=$(kubectl exec -n kube-system "$CILIUM_POD" -- cilium policy get 2>/dev/null || echo "")
    POLICY_DROPS=$(echo "$POLICY_STATS" | grep -oP 'Denied: \K\d+' | awk '{sum+=$1} END {print sum}' || echo "0")
    POLICY_ALLOWS=$(echo "$POLICY_STATS" | grep -oP 'Allowed: \K\d+' | awk '{sum+=$1} END {print sum}' || echo "0")

    # Get Cilium resource usage
    CILIUM_METRICS=$(kubectl top pod -n kube-system "$CILIUM_POD" --no-headers 2>/dev/null || echo "")
    if [ -n "$CILIUM_METRICS" ]; then
        EBPF_OVERHEAD_CPU=$(echo "$CILIUM_METRICS" | awk '{print $2}' | sed 's/m//')
        EBPF_OVERHEAD_MEMORY=$(echo "$CILIUM_METRICS" | awk '{print $3}' | sed 's/Mi//')
    fi

    echo "eBPF policy drops: $POLICY_DROPS"
    echo "eBPF policy allows: $POLICY_ALLOWS"
fi

# Calculate performance impact
BASELINE_TOTAL=$((BASELINE_ALLOWED_REQUESTS + BASELINE_DENIED_REQUESTS))
POLICY_TOTAL=$((POLICY_ALLOWED_REQUESTS + POLICY_DENIED_REQUESTS))

if [ $BASELINE_TOTAL -gt 0 ]; then
    THROUGHPUT_IMPACT=$(awk "BEGIN {printf \"%.2f\", (($POLICY_TOTAL - $BASELINE_TOTAL) / $BASELINE_TOTAL) * 100}")
else
    THROUGHPUT_IMPACT="N/A"
fi

# Generate JSON report
cat > "$OUTPUT_FILE" << EOF
{
  "test_type": "network-policy",
  "mesh_type": "$MESH_TYPE",
  "timestamp": "$TIMESTAMP",
  "namespace": "$NAMESPACE",
  "test_duration_seconds": $TEST_DURATION,
  "results": {
    "baseline": {
      "allowed_client_requests": $BASELINE_ALLOWED_REQUESTS,
      "denied_client_requests": $BASELINE_DENIED_REQUESTS,
      "total_requests": $BASELINE_TOTAL
    },
    "l3_l4_policy": {
      "allowed_client_requests": $POLICY_ALLOWED_REQUESTS,
      "denied_client_requests": $POLICY_DENIED_REQUESTS,
      "total_requests": $POLICY_TOTAL,
      "policy_enforcement_working": $([ $POLICY_DENIED_REQUESTS -lt $BASELINE_DENIED_REQUESTS ] && echo "true" || echo "false")
    },
    "l7_policy": {
      "allowed_client_requests": $L7_ALLOWED_REQUESTS,
      "denied_client_requests": $L7_DENIED_REQUESTS,
      "enabled": $([ "$MESH_TYPE" = "cilium" ] && echo "true" || echo "false")
    },
    "ebpf_metrics": {
      "policy_drops": $POLICY_DROPS,
      "policy_allows": $POLICY_ALLOWS,
      "overhead_cpu_millicores": $EBPF_OVERHEAD_CPU,
      "overhead_memory_mib": $EBPF_OVERHEAD_MEMORY
    },
    "performance_impact": {
      "throughput_change_percent": "$THROUGHPUT_IMPACT"
    }
  }
}
EOF

echo ""
echo "=== Network Policy Test Results ==="
echo "Baseline throughput: $BASELINE_TOTAL requests"
echo "With policy throughput: $POLICY_TOTAL requests"
echo "Throughput impact: ${THROUGHPUT_IMPACT}%"
echo "Policy enforcement: $([ $POLICY_DENIED_REQUESTS -lt $BASELINE_DENIED_REQUESTS ] && echo 'WORKING' || echo 'NOT WORKING')"
echo "eBPF overhead - CPU: ${EBPF_OVERHEAD_CPU}m, Memory: ${EBPF_OVERHEAD_MEMORY}Mi"
echo ""
echo "Results saved to: $OUTPUT_FILE"
echo ""

# Cleanup option
read -p "Clean up test namespace? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleaning up..."
    kubectl delete namespace "$NAMESPACE"
    echo "Cleanup complete!"
else
    echo "Namespace $NAMESPACE preserved for inspection"
fi

echo "=== Network Policy Performance Test Complete ==="
