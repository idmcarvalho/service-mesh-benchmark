#!/bin/bash
set -e

# eBPF-Specific Metrics Collection Script
# Collects Cilium/Hubble eBPF metrics for performance analysis

echo "=== Collecting eBPF Metrics ==="

# Configuration
RESULTS_DIR="${RESULTS_DIR:-../results}"
NAMESPACE="${NAMESPACE:-default}"
DURATION="${DURATION:-60}"
CILIUM_NAMESPACE="${CILIUM_NAMESPACE:-kube-system}"

# Create results directory
mkdir -p "$RESULTS_DIR/ebpf"

# Get timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
METRICS_FILE="$RESULTS_DIR/ebpf/ebpf_metrics_${TIMESTAMP}.json"

echo "Collection duration: ${DURATION}s"
echo "Timestamp: $TIMESTAMP"
echo ""

# Check if Cilium is installed
if ! kubectl get pods -n "$CILIUM_NAMESPACE" -l k8s-app=cilium &> /dev/null; then
    echo "ERROR: Cilium not detected. eBPF metrics collection requires Cilium."
    exit 1
fi

CILIUM_POD=$(kubectl get pod -n "$CILIUM_NAMESPACE" -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')
echo "Using Cilium pod: $CILIUM_POD"
echo ""

# 1. Collect eBPF Map Statistics
echo "Collecting eBPF map statistics..."
kubectl exec -n "$CILIUM_NAMESPACE" "$CILIUM_POD" -- cilium bpf metrics list > \
    "$RESULTS_DIR/ebpf/bpf_metrics_${TIMESTAMP}.txt" 2>/dev/null || echo "cilium bpf metrics not available"

# 2. Collect Connection Tracking (CT) Table
echo "Collecting connection tracking table..."
kubectl exec -n "$CILIUM_NAMESPACE" "$CILIUM_POD" -- cilium bpf ct list global > \
    "$RESULTS_DIR/ebpf/ct_table_${TIMESTAMP}.txt" 2>/dev/null || echo "CT table not available"

# Count active connections
CT_COUNT=$(kubectl exec -n "$CILIUM_NAMESPACE" "$CILIUM_POD" -- cilium bpf ct list global 2>/dev/null | wc -l || echo "0")
echo "Active connections in CT table: $CT_COUNT"

# 3. Collect eBPF Program Statistics
echo "Collecting eBPF program statistics..."
kubectl exec -n "$CILIUM_NAMESPACE" "$CILIUM_POD" -- bpftool prog show > \
    "$RESULTS_DIR/ebpf/bpf_progs_${TIMESTAMP}.txt" 2>/dev/null || echo "bpftool not available"

# 4. Collect eBPF Map Memory Usage
echo "Collecting eBPF map memory usage..."
kubectl exec -n "$CILIUM_NAMESPACE" "$CILIUM_POD" -- bpftool map show > \
    "$RESULTS_DIR/ebpf/bpf_maps_${TIMESTAMP}.txt" 2>/dev/null || echo "bpftool map not available"

# Calculate total eBPF memory usage
EBPF_MEMORY_KB=0
if kubectl exec -n "$CILIUM_NAMESPACE" "$CILIUM_POD" -- bpftool map show &> /dev/null; then
    EBPF_MEMORY_KB=$(kubectl exec -n "$CILIUM_NAMESPACE" "$CILIUM_POD" -- \
        bpftool map show 2>/dev/null | grep -oP 'max_entries \K\d+' | \
        awk '{sum+=$1} END {print int(sum/1024)}' || echo "0")
fi
echo "Estimated eBPF memory usage: ${EBPF_MEMORY_KB}KB"

# 5. Collect Hubble Flow Logs (if enabled)
echo "Collecting Hubble flow logs..."
if kubectl get svc -n "$CILIUM_NAMESPACE" hubble-relay &> /dev/null; then
    echo "Hubble is enabled, collecting flows..."

    # Port forward Hubble relay in background
    kubectl port-forward -n "$CILIUM_NAMESPACE" svc/hubble-relay 4245:80 &> /dev/null &
    PORT_FORWARD_PID=$!
    sleep 3

    # Collect flows for specified duration
    if command -v hubble &> /dev/null; then
        hubble observe --server localhost:4245 --output json --last 1000 > \
            "$RESULTS_DIR/ebpf/hubble_flows_${TIMESTAMP}.json" 2>/dev/null || echo "Failed to collect Hubble flows"

        # Collect flow statistics
        hubble observe --server localhost:4245 --last 1000 2>/dev/null | \
            grep -oP 'verdict \K\w+' | sort | uniq -c > \
            "$RESULTS_DIR/ebpf/hubble_verdicts_${TIMESTAMP}.txt" || echo "Flow stats unavailable"
    else
        echo "Hubble CLI not installed, skipping flow collection"
    fi

    # Clean up port forward
    kill $PORT_FORWARD_PID 2>/dev/null || true
else
    echo "Hubble not enabled, skipping flow collection"
fi

# 6. Collect L7 Policy Statistics
echo "Collecting L7 policy statistics..."
kubectl exec -n "$CILIUM_NAMESPACE" "$CILIUM_POD" -- cilium policy get > \
    "$RESULTS_DIR/ebpf/l7_policies_${TIMESTAMP}.txt" 2>/dev/null || echo "No L7 policies found"

# 7. Collect Network Policy Enforcement Stats
echo "Collecting network policy enforcement statistics..."
kubectl exec -n "$CILIUM_NAMESPACE" "$CILIUM_POD" -- cilium bpf policy get --all > \
    "$RESULTS_DIR/ebpf/policy_enforcement_${TIMESTAMP}.txt" 2>/dev/null || echo "Policy stats unavailable"

# 8. Collect Service Load Balancing Stats (kube-proxy replacement)
echo "Collecting eBPF service load balancing statistics..."
kubectl exec -n "$CILIUM_NAMESPACE" "$CILIUM_POD" -- cilium bpf lb list > \
    "$RESULTS_DIR/ebpf/ebpf_lb_${TIMESTAMP}.txt" 2>/dev/null || echo "LB stats unavailable"

LB_SERVICES=$(kubectl exec -n "$CILIUM_NAMESPACE" "$CILIUM_POD" -- cilium bpf lb list 2>/dev/null | grep -c "Service" || echo "0")
echo "eBPF load-balanced services: $LB_SERVICES"

# 9. Collect Bandwidth Manager Stats (if enabled)
echo "Collecting bandwidth manager statistics..."
kubectl exec -n "$CILIUM_NAMESPACE" "$CILIUM_POD" -- cilium bpf bandwidth list > \
    "$RESULTS_DIR/ebpf/bandwidth_${TIMESTAMP}.txt" 2>/dev/null || echo "Bandwidth manager not enabled"

# 10. Collect Endpoint Statistics
echo "Collecting endpoint statistics..."
kubectl exec -n "$CILIUM_NAMESPACE" "$CILIUM_POD" -- cilium endpoint list -o json > \
    "$RESULTS_DIR/ebpf/endpoints_${TIMESTAMP}.json" 2>/dev/null || echo "Endpoint stats unavailable"

ENDPOINT_COUNT=$(kubectl exec -n "$CILIUM_NAMESPACE" "$CILIUM_POD" -- cilium endpoint list 2>/dev/null | grep -c "ready" || echo "0")
echo "Total managed endpoints: $ENDPOINT_COUNT"

# 11. Collect BPF Datapath Statistics
echo "Collecting datapath statistics..."
kubectl exec -n "$CILIUM_NAMESPACE" "$CILIUM_POD" -- cilium bpf metrics list > \
    "$RESULTS_DIR/ebpf/datapath_metrics_${TIMESTAMP}.txt" 2>/dev/null || echo "Datapath metrics unavailable"

# Parse datapath metrics for drops, forwards, errors
DROPS=$(grep -oP 'Reason.*drops.*: \K\d+' "$RESULTS_DIR/ebpf/datapath_metrics_${TIMESTAMP}.txt" 2>/dev/null | awk '{sum+=$1} END {print sum}' || echo "0")
FORWARDS=$(grep -oP 'Forward.*: \K\d+' "$RESULTS_DIR/ebpf/datapath_metrics_${TIMESTAMP}.txt" 2>/dev/null | awk '{sum+=$1} END {print sum}' || echo "0")

echo "Datapath drops: $DROPS"
echo "Datapath forwards: $FORWARDS"

# 12. Collect XDP Statistics (if enabled)
echo "Collecting XDP statistics..."
kubectl exec -n "$CILIUM_NAMESPACE" "$CILIUM_POD" -- ip -s link show > \
    "$RESULTS_DIR/ebpf/xdp_stats_${TIMESTAMP}.txt" 2>/dev/null || echo "XDP stats unavailable"

# 13. Collect eBPF Performance Events
echo "Collecting eBPF performance counters..."
kubectl exec -n "$CILIUM_NAMESPACE" "$CILIUM_POD" -- cilium metrics list 2>/dev/null | \
    grep -E 'bpf_|ebpf_|datapath_' > "$RESULTS_DIR/ebpf/bpf_perf_${TIMESTAMP}.txt" || echo "BPF metrics unavailable"

# 14. Analyze Hubble Flow Statistics
FLOW_STATS_FORWARDED=0
FLOW_STATS_DROPPED=0
FLOW_HTTP_REQUESTS=0

if [ -f "$RESULTS_DIR/ebpf/hubble_verdicts_${TIMESTAMP}.txt" ]; then
    FLOW_STATS_FORWARDED=$(grep -i "forwarded" "$RESULTS_DIR/ebpf/hubble_verdicts_${TIMESTAMP}.txt" | awk '{print $1}' || echo "0")
    FLOW_STATS_DROPPED=$(grep -i "dropped" "$RESULTS_DIR/ebpf/hubble_verdicts_${TIMESTAMP}.txt" | awk '{print $1}' || echo "0")
fi

# 15. Calculate eBPF Overhead Metrics
echo ""
echo "Calculating eBPF overhead..."

# Get Cilium agent CPU/Memory
CILIUM_CPU=0
CILIUM_MEMORY=0
CILIUM_METRICS=$(kubectl top pod -n "$CILIUM_NAMESPACE" -l k8s-app=cilium --no-headers 2>/dev/null || echo "")
if [ -n "$CILIUM_METRICS" ]; then
    CILIUM_CPU=$(echo "$CILIUM_METRICS" | head -1 | awk '{print $2}' | sed 's/m//')
    CILIUM_MEMORY=$(echo "$CILIUM_METRICS" | head -1 | awk '{print $3}' | sed 's/Mi//')
fi

echo "Cilium agent CPU: ${CILIUM_CPU}m"
echo "Cilium agent memory: ${CILIUM_MEMORY}Mi"

# Generate comprehensive JSON report
cat > "$METRICS_FILE" << EOF
{
  "timestamp": "$TIMESTAMP",
  "collection_time": "$(date -Iseconds)",
  "duration_seconds": $DURATION,
  "cilium_pod": "$CILIUM_POD",
  "ebpf_metrics": {
    "connection_tracking": {
      "active_connections": $CT_COUNT
    },
    "memory_usage": {
      "ebpf_maps_kb": $EBPF_MEMORY_KB
    },
    "load_balancing": {
      "services_count": $LB_SERVICES
    },
    "endpoints": {
      "managed_count": $ENDPOINT_COUNT
    },
    "datapath": {
      "packets_dropped": $DROPS,
      "packets_forwarded": $FORWARDS
    },
    "flow_statistics": {
      "forwarded": $FLOW_STATS_FORWARDED,
      "dropped": $FLOW_STATS_DROPPED,
      "http_requests": $FLOW_HTTP_REQUESTS
    },
    "resource_usage": {
      "cilium_agent_cpu_millicores": $CILIUM_CPU,
      "cilium_agent_memory_mib": $CILIUM_MEMORY
    }
  },
  "files_collected": {
    "bpf_metrics": "ebpf/bpf_metrics_${TIMESTAMP}.txt",
    "connection_tracking": "ebpf/ct_table_${TIMESTAMP}.txt",
    "bpf_programs": "ebpf/bpf_progs_${TIMESTAMP}.txt",
    "bpf_maps": "ebpf/bpf_maps_${TIMESTAMP}.txt",
    "hubble_flows": "ebpf/hubble_flows_${TIMESTAMP}.json",
    "l7_policies": "ebpf/l7_policies_${TIMESTAMP}.txt",
    "ebpf_lb": "ebpf/ebpf_lb_${TIMESTAMP}.txt",
    "endpoints": "ebpf/endpoints_${TIMESTAMP}.json"
  }
}
EOF

echo ""
echo "=== eBPF Metrics Summary ==="
echo "Active connections: $CT_COUNT"
echo "eBPF memory: ${EBPF_MEMORY_KB}KB"
echo "Load-balanced services: $LB_SERVICES"
echo "Managed endpoints: $ENDPOINT_COUNT"
echo "Packets forwarded: $FORWARDS"
echo "Packets dropped: $DROPS"
echo "Cilium CPU: ${CILIUM_CPU}m"
echo "Cilium Memory: ${CILIUM_MEMORY}Mi"
echo ""
echo "Results saved to: $METRICS_FILE"
echo "=== eBPF Metrics Collection Complete ==="
