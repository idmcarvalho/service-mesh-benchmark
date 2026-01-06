# Workloads Directory

This directory contains all benchmark workloads, including Kubernetes manifests, execution scripts, and container images.

## Directory Structure

### [kubernetes/](kubernetes/)
Kubernetes manifests for benchmark workloads:
- `workloads/` - Deployment manifests for various workload types
  - `http-service.yaml` - HTTP/REST workload (Nginx + wrk)
  - `grpc-service.yaml` - gRPC workload (gRPC server + ghz)
  - `websocket-service.yaml` - WebSocket workload (echo server)
  - `database-cluster.yaml` - Database workload (Redis StatefulSet)
  - `ml-batch-job.yaml` - Machine learning batch job
  - `baseline-*.yaml` - Baseline workloads without service mesh
  - `health-check-service.yaml` - Health check validators
- `rbac/` - Role-Based Access Control configurations
  - `benchmark-runner.yaml` - Cluster-admin role for test execution
  - `workload-service-account.yaml` - Limited service account for workloads
- `network-policies/` - Kubernetes network policies
  - `default-deny.yaml` - Default deny-all policy
  - `allow-http-benchmark.yaml` - HTTP-specific rules
  - `allow-grpc-benchmark.yaml` - gRPC-specific rules
  - `allow-dns-egress.yaml` - DNS resolution rules
- `database/` - Stateful workloads
  - `postgres-statefulset.yaml` - PostgreSQL for results storage
- `backup/` - Backup automation
  - `backup-cronjob.yaml` - Scheduled results backup

### [scripts/](scripts/)
Benchmark execution and metrics collection scripts:
- `runners/` - Test execution scripts
  - `http-load-test.sh` - wrk-based HTTP load testing
  - `grpc-test.sh` - ghz-based gRPC benchmarking
  - `websocket-test.sh` - WebSocket stability testing
  - `ml-workload.sh` - ML job execution
- `metrics/` - Metrics collection scripts
  - `collect-metrics.sh` - Prometheus metrics aggregation
  - `collect-ebpf-metrics.sh` - eBPF probe data collection
  - `compare-overhead.sh` - Service mesh overhead analysis
- `validation/` - Validation scripts
  - `test-network-policies.sh` - Network policy validation
  - `test-l7-policies.sh` - L7 policy testing (Cilium-specific)
- `results/` - Output directory for benchmark results (gitignored)

### [docker/](docker/)
Container images for workloads:
- `api/` - FastAPI service Dockerfile
- `health-check/` - Health check service Dockerfile
- `ml-workload/` - ML workload Dockerfile

## Workload Types

### HTTP Workload
- **Purpose**: Measure HTTP/1.1 request latency and throughput
- **Components**: 3 Nginx replicas, wrk load test clients
- **Metrics**: RPS, latency percentiles (p50, p95, p99), error rate
- **Tool**: wrk (HTTP benchmarking tool)

### gRPC Workload
- **Purpose**: Measure gRPC streaming and unary call performance
- **Components**: 3 gRPC server replicas, ghz clients
- **Metrics**: RPS, latency, streaming throughput
- **Tool**: ghz (gRPC benchmarking tool)

### WebSocket Workload
- **Purpose**: Test long-lived connection stability
- **Components**: 3 WebSocket echo servers, persistent connections
- **Metrics**: Connection stability, message latency, reconnection rate
- **Tool**: Custom WebSocket client

### Database Workload
- **Purpose**: Measure stateful service performance
- **Components**: 3-node Redis StatefulSet, redis-benchmark clients
- **Metrics**: Operations/sec, latency, replication lag
- **Tool**: redis-benchmark

### Machine Learning Workload
- **Purpose**: Test resource-intensive batch processing
- **Components**: Batch job with scikit-learn RandomForest training
- **Metrics**: Job completion time, resource usage
- **Tool**: Custom Python script

## Running Benchmarks

### Deploy Workloads
```bash
# Deploy all workloads
kubectl apply -f workloads/kubernetes/workloads/

# Deploy RBAC
kubectl apply -f workloads/kubernetes/rbac/

# Deploy network policies
kubectl apply -f workloads/kubernetes/network-policies/
```

### Run Benchmark Scripts
```bash
# HTTP load test
./workloads/scripts/runners/http-load-test.sh

# gRPC test
./workloads/scripts/runners/grpc-test.sh

# Collect metrics
./workloads/scripts/metrics/collect-metrics.sh
```

### Build Container Images
```bash
# Build API image
docker build -t benchmark-api:latest workloads/docker/api/

# Build ML workload image
docker build -t ml-workload:latest workloads/docker/ml-workload/
```

## Results

Benchmark results are stored in `scripts/results/` with timestamps:
- `*.json` - Raw benchmark output
- `*.csv` - Aggregated metrics
- `report.html` - Generated comparison report

## Baseline vs Service Mesh

Each workload has two variants:
1. **Baseline** (`baseline-*.yaml`) - Direct pod-to-pod communication without service mesh
2. **Service Mesh** (standard manifests) - With Istio/Cilium/Linkerd/Consul injection

This allows for accurate overhead measurement and comparison.

## Security

All workloads run with:
- Non-root containers
- Read-only root filesystems
- Security contexts with minimal privileges
- Network policies for isolation
- Service accounts with RBAC

See [Security Documentation](../docs/security/) for details.
