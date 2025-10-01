#!/bin/bash
set -e

# Metrics Collection Script

echo "=== Collecting Service Mesh Metrics ==="

# Configuration
RESULTS_DIR="${RESULTS_DIR:-../results}"
NAMESPACE="${NAMESPACE:-default}"

# Create results directory
mkdir -p "$RESULTS_DIR"

# Get timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
METRICS_FILE="$RESULTS_DIR/metrics_${TIMESTAMP}.json"

echo "Collecting metrics from namespace: $NAMESPACE"
echo "Timestamp: $TIMESTAMP"

# Collect resource usage
echo "Collecting resource usage..."
kubectl top nodes > "$RESULTS_DIR/nodes_${TIMESTAMP}.txt"
kubectl top pods --all-namespaces > "$RESULTS_DIR/pods_all_${TIMESTAMP}.txt"

# Collect service mesh specific metrics
echo "Collecting service mesh metrics..."

# Check for Istio
if kubectl get namespace istio-system &> /dev/null; then
    echo "Detected Istio..."
    kubectl top pods -n istio-system > "$RESULTS_DIR/istio_pods_${TIMESTAMP}.txt"
    kubectl get pods -n istio-system -o wide > "$RESULTS_DIR/istio_pods_status_${TIMESTAMP}.txt"

    # Get Istio proxy metrics
    for pod in $(kubectl get pods -n http-benchmark -o name | grep -v client); do
        POD_NAME=$(echo $pod | cut -d/ -f2)
        kubectl exec -n http-benchmark $POD_NAME -c istio-proxy -- \
            curl -s http://localhost:15000/stats/prometheus > \
            "$RESULTS_DIR/istio_proxy_${POD_NAME}_${TIMESTAMP}.txt" 2>/dev/null || true
    done
fi

# Check for Cilium
if kubectl get namespace kube-system &> /dev/null && kubectl get pods -n kube-system -l k8s-app=cilium &> /dev/null; then
    echo "Detected Cilium..."
    kubectl get pods -n kube-system -l k8s-app=cilium -o wide > "$RESULTS_DIR/cilium_pods_${TIMESTAMP}.txt"
    kubectl top pods -n kube-system -l k8s-app=cilium > "$RESULTS_DIR/cilium_top_${TIMESTAMP}.txt"

    # Get Cilium metrics
    CILIUM_POD=$(kubectl get pod -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')
    kubectl exec -n kube-system $CILIUM_POD -- cilium metrics list > \
        "$RESULTS_DIR/cilium_metrics_${TIMESTAMP}.txt" 2>/dev/null || true
fi

# Check for Linkerd
if kubectl get namespace linkerd &> /dev/null; then
    echo "Detected Linkerd..."
    kubectl top pods -n linkerd > "$RESULTS_DIR/linkerd_pods_${TIMESTAMP}.txt"
    kubectl get pods -n linkerd -o wide > "$RESULTS_DIR/linkerd_pods_status_${TIMESTAMP}.txt"
fi

# Collect network statistics
echo "Collecting network statistics..."
kubectl get services --all-namespaces -o wide > "$RESULTS_DIR/services_${TIMESTAMP}.txt"
kubectl get endpoints --all-namespaces > "$RESULTS_DIR/endpoints_${TIMESTAMP}.txt"

# Collect pod logs from benchmark namespaces
echo "Collecting pod logs..."
for ns in http-benchmark grpc-benchmark websocket-benchmark db-benchmark ml-benchmark; do
    if kubectl get namespace $ns &> /dev/null; then
        for pod in $(kubectl get pods -n $ns -o name); do
            POD_NAME=$(echo $pod | cut -d/ -f2)
            kubectl logs -n $ns $POD_NAME --tail=100 > \
                "$RESULTS_DIR/${ns}_${POD_NAME}_logs_${TIMESTAMP}.txt" 2>/dev/null || true
        done
    fi
done

# Generate summary JSON
cat > "$METRICS_FILE" << EOF
{
  "timestamp": "$TIMESTAMP",
  "collection_time": "$(date -Iseconds)",
  "namespace": "$NAMESPACE",
  "metrics_collected": {
    "nodes": "nodes_${TIMESTAMP}.txt",
    "pods": "pods_all_${TIMESTAMP}.txt",
    "services": "services_${TIMESTAMP}.txt",
    "endpoints": "endpoints_${TIMESTAMP}.txt"
  }
}
EOF

echo "Metrics collected successfully!"
echo "Results saved to: $RESULTS_DIR"
echo "Summary: $METRICS_FILE"
echo "=== Metrics Collection Complete ==="
