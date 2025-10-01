#!/bin/bash
set -e

# ML Workload Benchmark Script

echo "=== ML Workload Benchmark ==="

# Configuration
RESULTS_DIR="${RESULTS_DIR:-../results}"
NAMESPACE="ml-benchmark"

# Create results directory
mkdir -p "$RESULTS_DIR"

# Get timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "Testing ML workloads in namespace: $NAMESPACE"

# Deploy ML jobs if not already deployed
if ! kubectl get namespace $NAMESPACE &> /dev/null; then
    echo "Creating $NAMESPACE namespace..."
    kubectl create namespace $NAMESPACE
fi

echo "Deploying ML training job..."
kubectl apply -f ../../kubernetes/workloads/ml-batch-job.yaml

# Monitor job completion
echo "Monitoring job progress..."
kubectl wait --for=condition=complete --timeout=600s job/ml-training-job -n $NAMESPACE || true

# Collect job statistics
echo "Collecting job statistics..."
kubectl describe job ml-training-job -n $NAMESPACE > "$RESULTS_DIR/ml_job_describe_${TIMESTAMP}.txt"
kubectl get jobs -n $NAMESPACE -o wide > "$RESULTS_DIR/ml_jobs_${TIMESTAMP}.txt"
kubectl get pods -n $NAMESPACE -o wide > "$RESULTS_DIR/ml_pods_${TIMESTAMP}.txt"

# Get pod logs
echo "Collecting pod logs..."
for pod in $(kubectl get pods -n $NAMESPACE -l app=ml-training -o name); do
    POD_NAME=$(echo $pod | cut -d/ -f2)
    kubectl logs -n $NAMESPACE $POD_NAME > "$RESULTS_DIR/ml_${POD_NAME}_${TIMESTAMP}.txt" 2>/dev/null || true
done

# Collect resource metrics
echo "Collecting resource metrics..."
kubectl top pods -n $NAMESPACE > "$RESULTS_DIR/ml_resources_${TIMESTAMP}.txt" || true

# Generate summary
COMPLETED=$(kubectl get job ml-training-job -n $NAMESPACE -o jsonpath='{.status.succeeded}')
FAILED=$(kubectl get job ml-training-job -n $NAMESPACE -o jsonpath='{.status.failed}')

cat > "$RESULTS_DIR/ml_summary_${TIMESTAMP}.json" << EOF
{
  "timestamp": "$TIMESTAMP",
  "namespace": "$NAMESPACE",
  "job_name": "ml-training-job",
  "completed": ${COMPLETED:-0},
  "failed": ${FAILED:-0},
  "results_dir": "$RESULTS_DIR"
}
EOF

echo "ML Workload benchmark complete!"
echo "Results saved to: $RESULTS_DIR"
echo "=== ML Workload Benchmark Complete ==="
