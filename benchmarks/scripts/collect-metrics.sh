#!/bin/bash
set -e

# Enhanced Metrics Collection Script with Service Mesh Control/Data Plane Metrics

echo "=== Collecting Service Mesh Metrics ==="

# Configuration
RESULTS_DIR="${RESULTS_DIR:-../results}"
NAMESPACE="${NAMESPACE:-default}"
MESH_TYPE="${MESH_TYPE:-auto}"  # auto, istio, cilium, linkerd, baseline

# Create results directory
mkdir -p "$RESULTS_DIR"

# Get timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
METRICS_FILE="$RESULTS_DIR/metrics_${TIMESTAMP}.json"

echo "Collecting metrics from namespace: $NAMESPACE"
echo "Timestamp: $TIMESTAMP"

# Initialize metrics JSON
DETECTED_MESH="baseline"
CONTROL_PLANE_CPU=0
CONTROL_PLANE_MEMORY=0
DATA_PLANE_CPU=0
DATA_PLANE_MEMORY=0

# Collect resource usage
echo "Collecting cluster resource usage..."
kubectl top nodes > "$RESULTS_DIR/nodes_${TIMESTAMP}.txt" 2>/dev/null || echo "kubectl top nodes not available"
kubectl top pods --all-namespaces > "$RESULTS_DIR/pods_all_${TIMESTAMP}.txt" 2>/dev/null || echo "kubectl top pods not available"

# Function to parse CPU (handles m suffix)
parse_cpu() {
    local cpu="$1"
    if [[ $cpu == *m ]]; then
        echo "${cpu%m}"
    else
        echo $((${cpu%.*} * 1000))
    fi
}

# Function to parse memory (handles Mi/Gi suffix)
parse_memory() {
    local mem="$1"
    if [[ $mem == *Mi ]]; then
        echo "${mem%Mi}"
    elif [[ $mem == *Gi ]]; then
        echo $(( ${mem%Gi} * 1024 ))
    else
        echo "${mem%.*}"
    fi
}

# Collect service mesh specific metrics
echo "Collecting service mesh metrics..."

# Check for Istio
if kubectl get namespace istio-system &> /dev/null; then
    DETECTED_MESH="istio"
    echo "Detected Istio..."

    # Control plane metrics
    kubectl top pods -n istio-system > "$RESULTS_DIR/istio_pods_${TIMESTAMP}.txt" 2>/dev/null || true
    kubectl get pods -n istio-system -o wide > "$RESULTS_DIR/istio_pods_status_${TIMESTAMP}.txt"

    # Calculate control plane resource usage
    CONTROL_PLANE_DATA=$(kubectl top pods -n istio-system --no-headers 2>/dev/null || echo "")
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            CPU=$(echo "$line" | awk '{print $2}')
            MEM=$(echo "$line" | awk '{print $3}')
            CONTROL_PLANE_CPU=$((CONTROL_PLANE_CPU + $(parse_cpu "$CPU")))
            CONTROL_PLANE_MEMORY=$((CONTROL_PLANE_MEMORY + $(parse_memory "$MEM")))
        fi
    done <<< "$CONTROL_PLANE_DATA"

    # Get Istio proxy (data plane) metrics from workload pods
    echo "Collecting Istio sidecar metrics..."
    for ns in http-benchmark grpc-benchmark websocket-benchmark baseline-http baseline-grpc; do
        if kubectl get namespace $ns &> /dev/null; then
            for pod in $(kubectl get pods -n $ns -o name 2>/dev/null | grep -v client); do
                POD_NAME=$(echo $pod | cut -d/ -f2)

                # Get proxy stats
                kubectl exec -n $ns $POD_NAME -c istio-proxy -- \
                    curl -s http://localhost:15000/stats/prometheus > \
                    "$RESULTS_DIR/istio_proxy_${POD_NAME}_${TIMESTAMP}.txt" 2>/dev/null || true

                # Get proxy resource usage
                POD_METRICS=$(kubectl top pod -n $ns $POD_NAME --containers --no-headers 2>/dev/null | grep istio-proxy || echo "")
                if [[ -n "$POD_METRICS" ]]; then
                    CPU=$(echo "$POD_METRICS" | awk '{print $3}')
                    MEM=$(echo "$POD_METRICS" | awk '{print $4}')
                    DATA_PLANE_CPU=$((DATA_PLANE_CPU + $(parse_cpu "$CPU")))
                    DATA_PLANE_MEMORY=$((DATA_PLANE_MEMORY + $(parse_memory "$MEM")))
                fi
            done
        fi
    done

    # Istio configuration
    kubectl get gateway,virtualservice,destinationrule --all-namespaces -o wide > \
        "$RESULTS_DIR/istio_config_${TIMESTAMP}.txt" 2>/dev/null || true
fi

# Check for Cilium
if kubectl get namespace kube-system &> /dev/null && kubectl get pods -n kube-system -l k8s-app=cilium &> /dev/null; then
    DETECTED_MESH="cilium"
    echo "Detected Cilium..."

    # Control plane metrics
    kubectl get pods -n kube-system -l k8s-app=cilium -o wide > "$RESULTS_DIR/cilium_pods_${TIMESTAMP}.txt"
    kubectl top pods -n kube-system -l k8s-app=cilium --no-headers 2>/dev/null > "$RESULTS_DIR/cilium_top_${TIMESTAMP}.txt" || true

    # Calculate Cilium agent resource usage (data plane)
    CILIUM_DATA=$(kubectl top pods -n kube-system -l k8s-app=cilium --no-headers 2>/dev/null || echo "")
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            CPU=$(echo "$line" | awk '{print $2}')
            MEM=$(echo "$line" | awk '{print $3}')
            DATA_PLANE_CPU=$((DATA_PLANE_CPU + $(parse_cpu "$CPU")))
            DATA_PLANE_MEMORY=$((DATA_PLANE_MEMORY + $(parse_memory "$MEM")))
        fi
    done <<< "$CILIUM_DATA"

    # Cilium operator (control plane)
    OPERATOR_DATA=$(kubectl top pods -n kube-system -l io.cilium/app=operator --no-headers 2>/dev/null || echo "")
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            CPU=$(echo "$line" | awk '{print $2}')
            MEM=$(echo "$line" | awk '{print $3}')
            CONTROL_PLANE_CPU=$((CONTROL_PLANE_CPU + $(parse_cpu "$CPU")))
            CONTROL_PLANE_MEMORY=$((CONTROL_PLANE_MEMORY + $(parse_memory "$MEM")))
        fi
    done <<< "$OPERATOR_DATA"

    # Get Cilium metrics
    CILIUM_POD=$(kubectl get pod -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [[ -n "$CILIUM_POD" ]]; then
        kubectl exec -n kube-system $CILIUM_POD -- cilium metrics list > \
            "$RESULTS_DIR/cilium_metrics_${TIMESTAMP}.txt" 2>/dev/null || true
        kubectl exec -n kube-system $CILIUM_POD -- cilium status > \
            "$RESULTS_DIR/cilium_status_${TIMESTAMP}.txt" 2>/dev/null || true
    fi

    # Cilium network policies
    kubectl get ciliumnetworkpolicies --all-namespaces -o wide > \
        "$RESULTS_DIR/cilium_policies_${TIMESTAMP}.txt" 2>/dev/null || true
fi

# Check for Linkerd
if kubectl get namespace linkerd &> /dev/null; then
    DETECTED_MESH="linkerd"
    echo "Detected Linkerd..."

    # Control plane metrics
    kubectl top pods -n linkerd --no-headers 2>/dev/null > "$RESULTS_DIR/linkerd_pods_${TIMESTAMP}.txt" || true
    kubectl get pods -n linkerd -o wide > "$RESULTS_DIR/linkerd_pods_status_${TIMESTAMP}.txt"

    # Calculate control plane resource usage
    CONTROL_PLANE_DATA=$(kubectl top pods -n linkerd --no-headers 2>/dev/null || echo "")
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            CPU=$(echo "$line" | awk '{print $2}')
            MEM=$(echo "$line" | awk '{print $3}')
            CONTROL_PLANE_CPU=$((CONTROL_PLANE_CPU + $(parse_cpu "$CPU")))
            CONTROL_PLANE_MEMORY=$((CONTROL_PLANE_MEMORY + $(parse_memory "$MEM")))
        fi
    done <<< "$CONTROL_PLANE_DATA"

    # Get Linkerd proxy (data plane) metrics
    echo "Collecting Linkerd proxy metrics..."
    for ns in http-benchmark grpc-benchmark websocket-benchmark baseline-http baseline-grpc; do
        if kubectl get namespace $ns &> /dev/null; then
            for pod in $(kubectl get pods -n $ns -o name 2>/dev/null | grep -v client); do
                POD_NAME=$(echo $pod | cut -d/ -f2)

                # Get proxy resource usage
                POD_METRICS=$(kubectl top pod -n $ns $POD_NAME --containers --no-headers 2>/dev/null | grep linkerd-proxy || echo "")
                if [[ -n "$POD_METRICS" ]]; then
                    CPU=$(echo "$POD_METRICS" | awk '{print $3}')
                    MEM=$(echo "$POD_METRICS" | awk '{print $4}')
                    DATA_PLANE_CPU=$((DATA_PLANE_CPU + $(parse_cpu "$CPU")))
                    DATA_PLANE_MEMORY=$((DATA_PLANE_MEMORY + $(parse_memory "$MEM")))
                fi
            done
        fi
    done
fi

# Collect network statistics
echo "Collecting network statistics..."
kubectl get services --all-namespaces -o wide > "$RESULTS_DIR/services_${TIMESTAMP}.txt"
kubectl get endpoints --all-namespaces > "$RESULTS_DIR/endpoints_${TIMESTAMP}.txt"

# Collect connection/packet statistics if available
echo "Collecting network connection metrics..."
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
    kubectl debug node/$node -it --image=nicolaka/netshoot -- \
        netstat -s > "$RESULTS_DIR/netstat_${node}_${TIMESTAMP}.txt" 2>/dev/null || true
done

# Collect pod logs from benchmark namespaces
echo "Collecting pod logs..."
for ns in http-benchmark grpc-benchmark websocket-benchmark db-benchmark ml-benchmark baseline-http baseline-grpc; do
    if kubectl get namespace $ns &> /dev/null; then
        for pod in $(kubectl get pods -n $ns -o name 2>/dev/null); do
            POD_NAME=$(echo $pod | cut -d/ -f2)
            kubectl logs -n $ns $POD_NAME --tail=100 > \
                "$RESULTS_DIR/${ns}_${POD_NAME}_logs_${TIMESTAMP}.txt" 2>/dev/null || true
        done
    fi
done

# Calculate total overhead percentages
TOTAL_MESH_CPU=$((CONTROL_PLANE_CPU + DATA_PLANE_CPU))
TOTAL_MESH_MEMORY=$((CONTROL_PLANE_MEMORY + DATA_PLANE_MEMORY))

# Generate enhanced summary JSON
cat > "$METRICS_FILE" << EOF
{
  "timestamp": "$TIMESTAMP",
  "collection_time": "$(date -Iseconds)",
  "namespace": "$NAMESPACE",
  "mesh_type": "$DETECTED_MESH",
  "resource_usage": {
    "control_plane": {
      "cpu_millicores": $CONTROL_PLANE_CPU,
      "memory_mib": $CONTROL_PLANE_MEMORY
    },
    "data_plane": {
      "cpu_millicores": $DATA_PLANE_CPU,
      "memory_mib": $DATA_PLANE_MEMORY
    },
    "total_mesh_overhead": {
      "cpu_millicores": $TOTAL_MESH_CPU,
      "memory_mib": $TOTAL_MESH_MEMORY
    }
  },
  "metrics_collected": {
    "nodes": "nodes_${TIMESTAMP}.txt",
    "pods": "pods_all_${TIMESTAMP}.txt",
    "services": "services_${TIMESTAMP}.txt",
    "endpoints": "endpoints_${TIMESTAMP}.txt"
  }
}
EOF

echo ""
echo "=== Metrics Summary ==="
echo "Detected Service Mesh: $DETECTED_MESH"
echo "Control Plane - CPU: ${CONTROL_PLANE_CPU}m, Memory: ${CONTROL_PLANE_MEMORY}Mi"
echo "Data Plane - CPU: ${DATA_PLANE_CPU}m, Memory: ${DATA_PLANE_MEMORY}Mi"
echo "Total Mesh Overhead - CPU: ${TOTAL_MESH_CPU}m, Memory: ${TOTAL_MESH_MEMORY}Mi"
echo ""
echo "Results saved to: $RESULTS_DIR"
echo "Summary: $METRICS_FILE"
echo "=== Metrics Collection Complete ==="
