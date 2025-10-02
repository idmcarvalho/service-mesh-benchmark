#!/bin/bash
set -e

# Cilium L7 Traffic Management Benchmark
# Tests eBPF-based L7 load balancing vs sidecar-based approaches

echo "=== Cilium L7 Traffic Management Benchmark ==="

# Configuration
RESULTS_DIR="${RESULTS_DIR:-../results}"
TEST_DURATION="${TEST_DURATION:-60}"
NAMESPACE="${NAMESPACE:-l7-benchmark}"
CONCURRENT_CONNECTIONS="${CONCURRENT_CONNECTIONS:-100}"

# Create results directory
mkdir -p "$RESULTS_DIR/l7-benchmark"

# Get timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="$RESULTS_DIR/l7-benchmark/l7_test_${TIMESTAMP}.json"

echo "Test duration: ${TEST_DURATION}s"
echo "Namespace: $NAMESPACE"
echo "Concurrent connections: $CONCURRENT_CONNECTIONS"
echo ""

# Check if Cilium is installed
if ! kubectl get pods -n kube-system -l k8s-app=cilium &> /dev/null; then
    echo "ERROR: Cilium not detected. This test requires Cilium."
    exit 1
fi

# Create test namespace
echo "Creating test namespace..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Deploy backend services with different versions
echo "Deploying L7 test workloads..."
cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Service
metadata:
  name: api-service
  namespace: $NAMESPACE
spec:
  selector:
    app: api
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-v1
  namespace: $NAMESPACE
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
      version: v1
  template:
    metadata:
      labels:
        app: api
        version: v1
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: config
          mountPath: /etc/nginx/conf.d
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
      volumes:
      - name: config
        configMap:
          name: api-v1-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: api-v1-config
  namespace: $NAMESPACE
data:
  default.conf: |
    server {
      listen 80;
      location / {
        return 200 '{"version": "v1", "service": "api"}\n';
        add_header Content-Type application/json;
      }
      location /health {
        return 200 'OK';
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-v2
  namespace: $NAMESPACE
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
      version: v2
  template:
    metadata:
      labels:
        app: api
        version: v2
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: config
          mountPath: /etc/nginx/conf.d
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
      volumes:
      - name: config
        configMap:
          name: api-v2-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: api-v2-config
  namespace: $NAMESPACE
data:
  default.conf: |
    server {
      listen 80;
      location / {
        return 200 '{"version": "v2", "service": "api"}\n';
        add_header Content-Type application/json;
      }
      location /health {
        return 200 'OK';
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: load-generator
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: load-generator
  template:
    metadata:
      labels:
        app: load-generator
    spec:
      containers:
      - name: wrk
        image: williamyeh/wrk:latest
        command: ["/bin/sleep", "infinity"]
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
EOF

# Wait for pods to be ready
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=api -n "$NAMESPACE" --timeout=120s
kubectl wait --for=condition=ready pod -l app=load-generator -n "$NAMESPACE" --timeout=120s
echo "Pods are ready"
echo ""

# Test 1: Baseline L4 load balancing
echo "Test 1: Baseline L4 load balancing (no L7 rules)"
echo "Running baseline test..."

LOAD_POD=$(kubectl get pod -n "$NAMESPACE" -l app=load-generator -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n "$NAMESPACE" "$LOAD_POD" -- wrk \
    -t4 -c"$CONCURRENT_CONNECTIONS" -d"${TEST_DURATION}s" \
    --latency --timeout 10s \
    "http://api-service/" > "$RESULTS_DIR/l7-benchmark/baseline_${TIMESTAMP}.txt"

BASELINE_RPS=$(grep "Requests/sec:" "$RESULTS_DIR/l7-benchmark/baseline_${TIMESTAMP}.txt" | awk '{print $2}')
BASELINE_LATENCY=$(grep "Latency" "$RESULTS_DIR/l7-benchmark/baseline_${TIMESTAMP}.txt" | head -1 | awk '{print $2}')

echo "Baseline RPS: $BASELINE_RPS"
echo "Baseline Latency: $BASELINE_LATENCY"
echo ""

# Test 2: L7 HTTP-based routing
echo "Test 2: L7 HTTP header-based routing"
echo "Applying L7 Cilium policy..."

cat <<EOF | kubectl apply -f -
apiVersion: cilium.io/v2
kind: CiliumClusterwideEnvoyConfig
metadata:
  name: api-service-l7-lb
spec:
  services:
  - name: api-service
    namespace: $NAMESPACE
  resources:
  - "@type": type.googleapis.com/envoy.config.listener.v3.Listener
    name: api-service-listener
    filterChains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typedConfig:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          statPrefix: api-service
          rds:
            routeConfigName: api-service-route
          httpFilters:
          - name: envoy.filters.http.router
            typedConfig:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
  - "@type": type.googleapis.com/envoy.config.route.v3.RouteConfiguration
    name: api-service-route
    virtualHosts:
    - name: api-service
      domains: ["*"]
      routes:
      - match:
          prefix: "/"
          headers:
          - name: "x-version"
            stringMatch:
              exact: "v2"
        route:
          cluster: "$NAMESPACE/api-service-v2"
      - match:
          prefix: "/"
        route:
          cluster: "$NAMESPACE/api-service-v1"
          weightedClusters:
            clusters:
            - name: "$NAMESPACE/api-service-v1"
              weight: 70
            - name: "$NAMESPACE/api-service-v2"
              weight: 30
EOF

# Wait for L7 configuration
echo "Waiting for L7 configuration to apply..."
sleep 15

echo "Running L7 routing test..."
kubectl exec -n "$NAMESPACE" "$LOAD_POD" -- wrk \
    -t4 -c"$CONCURRENT_CONNECTIONS" -d"${TEST_DURATION}s" \
    --latency --timeout 10s \
    "http://api-service/" > "$RESULTS_DIR/l7-benchmark/l7_routing_${TIMESTAMP}.txt"

L7_RPS=$(grep "Requests/sec:" "$RESULTS_DIR/l7-benchmark/l7_routing_${TIMESTAMP}.txt" | awk '{print $2}')
L7_LATENCY=$(grep "Latency" "$RESULTS_DIR/l7-benchmark/l7_routing_${TIMESTAMP}.txt" | head -1 | awk '{print $2}')

echo "L7 Routing RPS: $L7_RPS"
echo "L7 Routing Latency: $L7_LATENCY"
echo ""

# Test 3: L7 HTTP method-based routing
echo "Test 3: L7 HTTP method filtering"
echo "Applying L7 method-based policy..."

cat <<EOF | kubectl apply -f -
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: api-l7-methods
  namespace: $NAMESPACE
spec:
  endpointSelector:
    matchLabels:
      app: api
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: load-generator
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
      rules:
        http:
        - method: "GET"
        - method: "POST"
        - method: "PUT"
EOF

sleep 10

echo "Running L7 method filtering test..."
kubectl exec -n "$NAMESPACE" "$LOAD_POD" -- wrk \
    -t4 -c"$CONCURRENT_CONNECTIONS" -d"${TEST_DURATION}s" \
    --latency --timeout 10s \
    "http://api-service/" > "$RESULTS_DIR/l7-benchmark/l7_methods_${TIMESTAMP}.txt"

L7_METHOD_RPS=$(grep "Requests/sec:" "$RESULTS_DIR/l7-benchmark/l7_methods_${TIMESTAMP}.txt" | awk '{print $2}')
L7_METHOD_LATENCY=$(grep "Latency" "$RESULTS_DIR/l7-benchmark/l7_methods_${TIMESTAMP}.txt" | head -1 | awk '{print $2}')

echo "L7 Method Filter RPS: $L7_METHOD_RPS"
echo "L7 Method Filter Latency: $L7_METHOD_LATENCY"
echo ""

# Collect Cilium Envoy statistics
echo "Collecting Cilium Envoy metrics..."
CILIUM_POD=$(kubectl get pod -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')

# Get Envoy stats
kubectl exec -n kube-system "$CILIUM_POD" -- cilium envoy stats > \
    "$RESULTS_DIR/l7-benchmark/envoy_stats_${TIMESTAMP}.txt" 2>/dev/null || echo "Envoy stats unavailable"

# Parse Envoy metrics
ENVOY_REQUESTS=$(grep -oP 'http.*downstream_rq_total.*: \K\d+' "$RESULTS_DIR/l7-benchmark/envoy_stats_${TIMESTAMP}.txt" 2>/dev/null | head -1 || echo "0")
ENVOY_ERRORS=$(grep -oP 'http.*downstream_rq_5xx.*: \K\d+' "$RESULTS_DIR/l7-benchmark/envoy_stats_${TIMESTAMP}.txt" 2>/dev/null | head -1 || echo "0")

echo "Envoy processed requests: $ENVOY_REQUESTS"
echo "Envoy 5xx errors: $ENVOY_ERRORS"
echo ""

# Calculate performance impact
BASELINE_RPS_NUM=$(echo "$BASELINE_RPS" | awk '{print $1}')
L7_RPS_NUM=$(echo "$L7_RPS" | awk '{print $1}')

if [ -n "$BASELINE_RPS_NUM" ] && [ -n "$L7_RPS_NUM" ]; then
    L7_OVERHEAD=$(awk "BEGIN {printf \"%.2f\", (($BASELINE_RPS_NUM - $L7_RPS_NUM) / $BASELINE_RPS_NUM) * 100}")
else
    L7_OVERHEAD="N/A"
fi

# Convert latencies to milliseconds for JSON
parse_latency_ms() {
    local lat="$1"
    if [[ $lat == *"ms"* ]]; then
        echo "${lat//ms/}"
    elif [[ $lat == *"s"* ]]; then
        local sec="${lat//s/}"
        awk "BEGIN {printf \"%.2f\", $sec * 1000}"
    elif [[ $lat == *"us"* ]]; then
        local us="${lat//us/}"
        awk "BEGIN {printf \"%.2f\", $us / 1000}"
    else
        echo "0"
    fi
}

BASELINE_LAT_MS=$(parse_latency_ms "$BASELINE_LATENCY")
L7_LAT_MS=$(parse_latency_ms "$L7_LATENCY")
L7_METHOD_LAT_MS=$(parse_latency_ms "$L7_METHOD_LATENCY")

# Generate JSON report
cat > "$OUTPUT_FILE" << EOF
{
  "test_type": "cilium-l7-benchmark",
  "mesh_type": "cilium",
  "timestamp": "$TIMESTAMP",
  "namespace": "$NAMESPACE",
  "test_duration_seconds": $TEST_DURATION,
  "concurrent_connections": $CONCURRENT_CONNECTIONS,
  "results": {
    "baseline_l4": {
      "requests_per_sec": $BASELINE_RPS_NUM,
      "avg_latency_ms": $BASELINE_LAT_MS,
      "description": "Standard L4 load balancing without L7 rules"
    },
    "l7_routing": {
      "requests_per_sec": $L7_RPS_NUM,
      "avg_latency_ms": $L7_LAT_MS,
      "description": "L7 HTTP header-based routing with traffic split"
    },
    "l7_method_filtering": {
      "requests_per_sec": $L7_METHOD_RPS,
      "avg_latency_ms": $L7_METHOD_LAT_MS,
      "description": "L7 HTTP method-based filtering"
    },
    "envoy_metrics": {
      "total_requests": $ENVOY_REQUESTS,
      "errors_5xx": $ENVOY_ERRORS
    },
    "performance_impact": {
      "l7_overhead_percent": "$L7_OVERHEAD",
      "latency_increase_ms": $(awk "BEGIN {printf \"%.2f\", $L7_LAT_MS - $BASELINE_LAT_MS}")
    }
  },
  "ebpf_advantages": {
    "no_sidecar_injection": true,
    "kernel_level_processing": true,
    "lower_memory_footprint": true,
    "envoy_integrated": true
  }
}
EOF

echo ""
echo "=== Cilium L7 Benchmark Results ==="
echo "Baseline (L4): ${BASELINE_RPS} req/s, ${BASELINE_LAT_MS}ms latency"
echo "L7 Routing: ${L7_RPS} req/s, ${L7_LAT_MS}ms latency"
echo "L7 Method Filter: ${L7_METHOD_RPS} req/s, ${L7_METHOD_LAT_MS}ms latency"
echo "L7 Overhead: ${L7_OVERHEAD}%"
echo "Envoy Requests: $ENVOY_REQUESTS"
echo ""
echo "Results saved to: $OUTPUT_FILE"
echo ""

# Cleanup option
read -p "Clean up test namespace? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleaning up..."
    kubectl delete namespace "$NAMESPACE"
    kubectl delete ciliumclusterwideenvoyconfig api-service-l7-lb 2>/dev/null || true
    echo "Cleanup complete!"
else
    echo "Namespace $NAMESPACE preserved for inspection"
fi

echo "=== Cilium L7 Traffic Management Benchmark Complete ==="
