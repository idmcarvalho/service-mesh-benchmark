#!/bin/bash
set -e

# eBPF vs Sidecar Performance Comparison
# Compares Cilium (eBPF) vs Istio (sidecar) vs Baseline (no mesh)

echo "=== eBPF vs Sidecar Performance Comparison ==="

# Configuration
RESULTS_DIR="${RESULTS_DIR:-../results}"
TEST_DURATION="${TEST_DURATION:-60}"
CONCURRENT_CONNECTIONS="${CONCURRENT_CONNECTIONS:-100}"
WARMUP_DURATION="${WARMUP_DURATION:-10}"
COOLDOWN_DURATION="${COOLDOWN_DURATION:-5}"

# Create results directory
mkdir -p "$RESULTS_DIR/comparison"

# Get timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="$RESULTS_DIR/comparison/ebpf_vs_sidecar_${TIMESTAMP}.json"

echo "Test duration: ${TEST_DURATION}s per mesh"
echo "Concurrent connections: $CONCURRENT_CONNECTIONS"
echo ""

# Initialize result arrays
declare -A THROUGHPUT
declare -A LATENCY_AVG
declare -A LATENCY_P95
declare -A LATENCY_P99
declare -A CPU_CONTROL
declare -A MEMORY_CONTROL
declare -A CPU_DATA
declare -A MEMORY_DATA
declare -A SIDECAR_COUNT

# Function to run HTTP test
run_http_test() {
    local mesh_type="$1"
    local namespace="$2"
    local service_url="$3"

    echo "Testing $mesh_type..."
    echo "  Namespace: $namespace"
    echo "  Service: $service_url"

    # Health check
    if ! kubectl wait --for=condition=ready pod -l app=http-server -n "$namespace" --timeout=120s 2>/dev/null; then
        if ! kubectl wait --for=condition=ready pod -l app=baseline-http-server -n "$namespace" --timeout=120s 2>/dev/null; then
            echo "  Warning: Pods may not be ready"
        fi
    fi

    # Warm-up
    echo "  Running warm-up (${WARMUP_DURATION}s)..."
    kubectl run test-warmup --image=curlimages/curl:latest --rm -i --restart=Never -n "$namespace" -- \
        sh -c "for i in \$(seq 1 $((WARMUP_DURATION * 10))); do curl -s http://$service_url/ > /dev/null || true; sleep 0.1; done" &> /dev/null || true

    # Run test
    echo "  Running load test (${TEST_DURATION}s)..."
    TEST_RESULT="/tmp/test_${mesh_type}_${TIMESTAMP}.txt"

    kubectl run test-wrk-$mesh_type --image=williamyeh/wrk:latest --rm -i --restart=Never -n "$namespace" -- \
        wrk -t4 -c$CONCURRENT_CONNECTIONS -d${TEST_DURATION}s --latency --timeout 10s \
        "http://$service_url/" > "$TEST_RESULT" 2>&1 || true

    # Parse results
    if [ -f "$TEST_RESULT" ]; then
        THROUGHPUT[$mesh_type]=$(grep "Requests/sec:" "$TEST_RESULT" | awk '{print $2}' || echo "0")
        LAT_AVG=$(grep "Latency" "$TEST_RESULT" | head -1 | awk '{print $2}')
        LAT_P95=$(grep "95%" "$TEST_RESULT" | awk '{print $2}' || echo "N/A")
        LAT_P99=$(grep "99%" "$TEST_RESULT" | awk '{print $2}' || echo "N/A")

        # Convert to milliseconds
        LATENCY_AVG[$mesh_type]=$(convert_to_ms "$LAT_AVG")
        LATENCY_P95[$mesh_type]=$(convert_to_ms "$LAT_P95")
        LATENCY_P99[$mesh_type]=$(convert_to_ms "$LAT_P99")

        cp "$TEST_RESULT" "$RESULTS_DIR/comparison/${mesh_type}_wrk_${TIMESTAMP}.txt"
    else
        echo "  ERROR: Test failed for $mesh_type"
        THROUGHPUT[$mesh_type]=0
        LATENCY_AVG[$mesh_type]=0
        LATENCY_P95[$mesh_type]=0
        LATENCY_P99[$mesh_type]=0
    fi

    # Cool-down
    echo "  Cool-down (${COOLDOWN_DURATION}s)..."
    sleep "$COOLDOWN_DURATION"

    echo "  Results: ${THROUGHPUT[$mesh_type]} req/s, ${LATENCY_AVG[$mesh_type]}ms avg latency"
    echo ""
}

# Function to convert latency to milliseconds
convert_to_ms() {
    local lat="$1"
    if [[ $lat == *"ms"* ]]; then
        echo "${lat//ms/}"
    elif [[ $lat == *"s"* ]]; then
        local sec="${lat//s/}"
        awk "BEGIN {printf \"%.2f\", $sec * 1000}" 2>/dev/null || echo "0"
    elif [[ $lat == *"us"* ]]; then
        local us="${lat//us/}"
        awk "BEGIN {printf \"%.2f\", $us / 1000}" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Function to collect mesh resource metrics
collect_mesh_metrics() {
    local mesh_type="$1"

    echo "Collecting $mesh_type resource metrics..."

    if [ "$mesh_type" = "baseline" ]; then
        CPU_CONTROL[$mesh_type]=0
        MEMORY_CONTROL[$mesh_type]=0
        CPU_DATA[$mesh_type]=0
        MEMORY_DATA[$mesh_type]=0
        SIDECAR_COUNT[$mesh_type]=0

    elif [ "$mesh_type" = "cilium" ]; then
        # Cilium uses eBPF - no sidecars
        SIDECAR_COUNT[$mesh_type]=0

        # Get Cilium control plane (operator)
        OPERATOR_METRICS=$(kubectl top pods -n kube-system -l io.cilium/app=operator --no-headers 2>/dev/null || echo "")
        if [ -n "$OPERATOR_METRICS" ]; then
            CPU_CONTROL[$mesh_type]=$(echo "$OPERATOR_METRICS" | awk '{sum += substr($2,1,length($2)-1)} END {print int(sum)}')
            MEMORY_CONTROL[$mesh_type]=$(echo "$OPERATOR_METRICS" | awk '{sum += substr($3,1,length($3)-2)} END {print int(sum)}')
        else
            CPU_CONTROL[$mesh_type]=0
            MEMORY_CONTROL[$mesh_type]=0
        fi

        # Get Cilium data plane (agents - eBPF)
        AGENT_METRICS=$(kubectl top pods -n kube-system -l k8s-app=cilium --no-headers 2>/dev/null || echo "")
        if [ -n "$AGENT_METRICS" ]; then
            CPU_DATA[$mesh_type]=$(echo "$AGENT_METRICS" | awk '{sum += substr($2,1,length($2)-1)} END {print int(sum)}')
            MEMORY_DATA[$mesh_type]=$(echo "$AGENT_METRICS" | awk '{sum += substr($3,1,length($3)-2)} END {print int(sum)}')
        else
            CPU_DATA[$mesh_type]=0
            MEMORY_DATA[$mesh_type]=0
        fi

    elif [ "$mesh_type" = "istio" ]; then
        # Istio control plane
        CP_METRICS=$(kubectl top pods -n istio-system --no-headers 2>/dev/null || echo "")
        if [ -n "$CP_METRICS" ]; then
            CPU_CONTROL[$mesh_type]=$(echo "$CP_METRICS" | awk '{sum += substr($2,1,length($2)-1)} END {print int(sum)}')
            MEMORY_CONTROL[$mesh_type]=$(echo "$CP_METRICS" | awk '{sum += substr($3,1,length($3)-2)} END {print int(sum)}')
        else
            CPU_CONTROL[$mesh_type]=0
            MEMORY_CONTROL[$mesh_type]=0
        fi

        # Istio sidecars (data plane)
        SIDECAR_COUNT[$mesh_type]=$(kubectl get pods -n http-benchmark -o json 2>/dev/null | jq '[.items[] | select(.spec.containers | length > 1)] | length' || echo "0")

        # Estimate sidecar resource usage (approximate from top)
        TOTAL_POD_CPU=$(kubectl top pods -n http-benchmark --no-headers 2>/dev/null | grep http-server | awk '{sum += substr($2,1,length($2)-1)} END {print int(sum)}' || echo "0")
        TOTAL_POD_MEM=$(kubectl top pods -n http-benchmark --no-headers 2>/dev/null | grep http-server | awk '{sum += substr($3,1,length($3)-2)} END {print int(sum)}' || echo "0")

        # Assume ~40% of pod resources are sidecar (typical Envoy overhead)
        CPU_DATA[$mesh_type]=$(awk "BEGIN {print int($TOTAL_POD_CPU * 0.4)}")
        MEMORY_DATA[$mesh_type]=$(awk "BEGIN {print int($TOTAL_POD_MEM * 0.4)}")
    fi

    echo "  Control Plane: ${CPU_CONTROL[$mesh_type]}m CPU, ${MEMORY_CONTROL[$mesh_type]}Mi RAM"
    echo "  Data Plane: ${CPU_DATA[$mesh_type]}m CPU, ${MEMORY_DATA[$mesh_type]}Mi RAM"
    echo "  Sidecars: ${SIDECAR_COUNT[$mesh_type]}"
    echo ""
}

# Run tests for each mesh configuration

# 1. Baseline (no mesh)
echo "========================================="
echo "Test 1: Baseline (No Service Mesh)"
echo "========================================="
if kubectl get namespace baseline-http &> /dev/null; then
    run_http_test "baseline" "baseline-http" "baseline-http-server.baseline-http.svc.cluster.local"
    collect_mesh_metrics "baseline"
else
    echo "Baseline namespace not found. Skipping..."
    THROUGHPUT[baseline]=0
    LATENCY_AVG[baseline]=0
fi

# 2. Cilium (eBPF-based)
echo "========================================="
echo "Test 2: Cilium (eBPF-based)"
echo "========================================="
if kubectl get pods -n kube-system -l k8s-app=cilium &> /dev/null; then
    if kubectl get namespace http-benchmark &> /dev/null; then
        run_http_test "cilium" "http-benchmark" "http-server.http-benchmark.svc.cluster.local"
        collect_mesh_metrics "cilium"
    else
        echo "http-benchmark namespace not found. Skipping..."
        THROUGHPUT[cilium]=0
        LATENCY_AVG[cilium]=0
    fi
else
    echo "Cilium not installed. Skipping..."
    THROUGHPUT[cilium]=0
    LATENCY_AVG[cilium]=0
fi

# 3. Istio (sidecar-based)
echo "========================================="
echo "Test 3: Istio (Sidecar-based)"
echo "========================================="
if kubectl get namespace istio-system &> /dev/null; then
    if kubectl get namespace http-benchmark &> /dev/null; then
        run_http_test "istio" "http-benchmark" "http-server.http-benchmark.svc.cluster.local"
        collect_mesh_metrics "istio"
    else
        echo "http-benchmark namespace not found. Skipping..."
        THROUGHPUT[istio]=0
        LATENCY_AVG[istio]=0
    fi
else
    echo "Istio not installed. Skipping..."
    THROUGHPUT[istio]=0
    LATENCY_AVG[istio]=0
fi

# Calculate performance differences
echo "========================================="
echo "Calculating Performance Metrics"
echo "========================================="

BASELINE_RPS=${THROUGHPUT[baseline]:-1}
if [ "$BASELINE_RPS" = "0" ]; then
    BASELINE_RPS=1
fi

# Calculate overhead percentages
CILIUM_OVERHEAD=$(awk "BEGIN {printf \"%.2f\", (($BASELINE_RPS - ${THROUGHPUT[cilium]:-0}) / $BASELINE_RPS) * 100}" 2>/dev/null || echo "N/A")
ISTIO_OVERHEAD=$(awk "BEGIN {printf \"%.2f\", (($BASELINE_RPS - ${THROUGHPUT[istio]:-0}) / $BASELINE_RPS) * 100}" 2>/dev/null || echo "N/A")

# Calculate latency increases
CILIUM_LAT_INCREASE=$(awk "BEGIN {printf \"%.2f\", ${LATENCY_AVG[cilium]:-0} - ${LATENCY_AVG[baseline]:-0}}" 2>/dev/null || echo "0")
ISTIO_LAT_INCREASE=$(awk "BEGIN {printf \"%.2f\", ${LATENCY_AVG[istio]:-0} - ${LATENCY_AVG[baseline]:-0}}" 2>/dev/null || echo "0")

# Generate comprehensive JSON report
cat > "$OUTPUT_FILE" << EOF
{
  "test_type": "ebpf-vs-sidecar-comparison",
  "timestamp": "$TIMESTAMP",
  "test_duration_seconds": $TEST_DURATION,
  "concurrent_connections": $CONCURRENT_CONNECTIONS,
  "results": {
    "baseline": {
      "throughput_rps": ${THROUGHPUT[baseline]:-0},
      "latency_avg_ms": ${LATENCY_AVG[baseline]:-0},
      "latency_p95_ms": ${LATENCY_P95[baseline]:-0},
      "latency_p99_ms": ${LATENCY_P99[baseline]:-0},
      "control_plane_cpu_millicores": ${CPU_CONTROL[baseline]:-0},
      "control_plane_memory_mib": ${MEMORY_CONTROL[baseline]:-0},
      "data_plane_cpu_millicores": ${CPU_DATA[baseline]:-0},
      "data_plane_memory_mib": ${MEMORY_DATA[baseline]:-0},
      "sidecar_count": ${SIDECAR_COUNT[baseline]:-0}
    },
    "cilium_ebpf": {
      "throughput_rps": ${THROUGHPUT[cilium]:-0},
      "latency_avg_ms": ${LATENCY_AVG[cilium]:-0},
      "latency_p95_ms": ${LATENCY_P95[cilium]:-0},
      "latency_p99_ms": ${LATENCY_P99[cilium]:-0},
      "control_plane_cpu_millicores": ${CPU_CONTROL[cilium]:-0},
      "control_plane_memory_mib": ${MEMORY_CONTROL[cilium]:-0},
      "data_plane_cpu_millicores": ${CPU_DATA[cilium]:-0},
      "data_plane_memory_mib": ${MEMORY_DATA[cilium]:-0},
      "sidecar_count": ${SIDECAR_COUNT[cilium]:-0},
      "throughput_overhead_percent": "$CILIUM_OVERHEAD",
      "latency_increase_ms": "$CILIUM_LAT_INCREASE",
      "ebpf_advantages": [
        "No sidecar injection required",
        "Kernel-level packet processing",
        "Lower memory footprint per pod",
        "Native Linux integration",
        "XDP acceleration capability"
      ]
    },
    "istio_sidecar": {
      "throughput_rps": ${THROUGHPUT[istio]:-0},
      "latency_avg_ms": ${LATENCY_AVG[istio]:-0},
      "latency_p95_ms": ${LATENCY_P95[istio]:-0},
      "latency_p99_ms": ${LATENCY_P99[istio]:-0},
      "control_plane_cpu_millicores": ${CPU_CONTROL[istio]:-0},
      "control_plane_memory_mib": ${MEMORY_CONTROL[istio]:-0},
      "data_plane_cpu_millicores": ${CPU_DATA[istio]:-0},
      "data_plane_memory_mib": ${MEMORY_DATA[istio]:-0},
      "sidecar_count": ${SIDECAR_COUNT[istio]:-0},
      "throughput_overhead_percent": "$ISTIO_OVERHEAD",
      "latency_increase_ms": "$ISTIO_LAT_INCREASE",
      "sidecar_characteristics": [
        "Per-pod sidecar proxy (Envoy)",
        "Additional memory per pod",
        "Full L7 protocol support",
        "Rich observability features",
        "Mature ecosystem"
      ]
    }
  },
  "comparison_summary": {
    "cilium_vs_istio": {
      "throughput_advantage_percent": $(awk "BEGIN {printf \"%.2f\", ((${THROUGHPUT[cilium]:-0} - ${THROUGHPUT[istio]:-0}) / ${THROUGHPUT[istio]:-1}) * 100}" 2>/dev/null || echo "0"),
      "latency_advantage_ms": $(awk "BEGIN {printf \"%.2f\", ${LATENCY_AVG[istio]:-0} - ${LATENCY_AVG[cilium]:-0}}" 2>/dev/null || echo "0"),
      "memory_savings_mib": $((${MEMORY_DATA[istio]:-0} - ${MEMORY_DATA[cilium]:-0})),
      "cpu_savings_millicores": $((${CPU_DATA[istio]:-0} - ${CPU_DATA[cilium]:-0}))
    },
    "recommendations": {
      "choose_cilium_if": [
        "Resource efficiency is critical",
        "Lower latency is priority",
        "Native kernel integration preferred",
        "No per-pod sidecar overhead acceptable"
      ],
      "choose_istio_if": [
        "Mature ecosystem required",
        "Complex L7 routing needed",
        "Multi-cluster federation required",
        "Rich observability features essential"
      ]
    }
  }
}
EOF

# Display summary
echo ""
echo "=== Performance Comparison Summary ==="
echo ""
echo "Throughput (req/s):"
echo "  Baseline:  ${THROUGHPUT[baseline]:-N/A}"
echo "  Cilium:    ${THROUGHPUT[cilium]:-N/A} (overhead: ${CILIUM_OVERHEAD}%)"
echo "  Istio:     ${THROUGHPUT[istio]:-N/A} (overhead: ${ISTIO_OVERHEAD}%)"
echo ""
echo "Average Latency (ms):"
echo "  Baseline:  ${LATENCY_AVG[baseline]:-N/A}"
echo "  Cilium:    ${LATENCY_AVG[cilium]:-N/A} (+${CILIUM_LAT_INCREASE}ms)"
echo "  Istio:     ${LATENCY_AVG[istio]:-N/A} (+${ISTIO_LAT_INCREASE}ms)"
echo ""
echo "Resource Overhead:"
echo "  Cilium:    ${CPU_DATA[cilium]:-0}m CPU, ${MEMORY_DATA[cilium]:-0}Mi RAM, ${SIDECAR_COUNT[cilium]:-0} sidecars"
echo "  Istio:     ${CPU_DATA[istio]:-0}m CPU, ${MEMORY_DATA[istio]:-0}Mi RAM, ${SIDECAR_COUNT[istio]:-0} sidecars"
echo ""
echo "eBPF Advantages (Cilium):"
echo "  - No sidecar injection"
echo "  - Kernel-level processing"
echo "  - Lower memory per pod"
echo "  - CPU savings: $((${CPU_DATA[istio]:-0} - ${CPU_DATA[cilium]:-0}))m"
echo "  - Memory savings: $((${MEMORY_DATA[istio]:-0} - ${MEMORY_DATA[cilium]:-0}))Mi"
echo ""
echo "Results saved to: $OUTPUT_FILE"
echo "=== Comparison Complete ==="
