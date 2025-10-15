# Service Mesh Benchmark Testing Guide

Comprehensive testing documentation for the service mesh benchmark framework.

## Table of Contents

- [Overview](#overview)
- [Test Framework](#test-framework)
- [Testing Phases](#testing-phases)
- [Quick Start](#quick-start)
- [Test Commands](#test-commands)
- [Health Checks](#health-checks)
- [Test Results](#test-results)
- [CI/CD Integration](#cicd-integration)
- [Troubleshooting](#troubleshooting)

## Overview

The testing framework provides comprehensive validation across 7 phases:

1. **Phase 1**: Pre-deployment validation
2. **Phase 2**: Infrastructure verification
3. **Phase 3**: Baseline performance testing
4. **Phase 4**: Service mesh testing (Istio/Cilium/Linkerd)
5. **Phase 5**: Cilium-specific tests
6. **Phase 6**: Comparative analysis
7. **Phase 7**: Stress and edge case testing

## Test Framework

### Technology Stack

- **Framework**: pytest 8.0.0
- **Language**: Python 3.11+
- **Kubernetes Client**: kubernetes-python
- **Infrastructure**: Terraform validation
- **Load Testing**: wrk, Apache Bench, ghz (via existing scripts)

### Directory Structure

```
tests/
├── conftest.py                    # Pytest configuration and fixtures
├── pytest.ini                     # Pytest settings
├── requirements.txt               # Python dependencies
├── run_tests.py                   # Test orchestration script
├── test_phase1_predeployment.py  # Pre-deployment tests
├── test_phase2_infrastructure.py  # Infrastructure tests
├── test_phase3_baseline.py        # Baseline performance tests
├── test_phase4_servicemesh.py     # Service mesh tests
├── test_phase6_comparative.py     # Comparative analysis
└── test_phase7_stress.py          # Stress tests
```

## Testing Phases

### Phase 1: Pre-deployment Validation

**Purpose**: Validate environment and configuration before deployment
**Duration**: < 5 minutes
**Requirements**: None (runs locally)

Tests:
- ✅ Terraform installed and configuration valid
- ✅ kubectl installed and working
- ✅ Python dependencies available
- ✅ Kubernetes manifests valid YAML
- ✅ Benchmark scripts exist and executable
- ✅ Health checks defined in workloads
- ✅ Resource limits configured
- ✅ No hardcoded credentials
- ✅ .gitignore configured properly

```bash
# Run Phase 1
make test-validate
```

### Phase 2: Infrastructure Validation

**Purpose**: Verify deployed infrastructure and Kubernetes cluster
**Duration**: 5-10 minutes
**Requirements**: Deployed infrastructure, kubeconfig

Tests:
- ✅ Kubernetes cluster accessible
- ✅ All nodes in Ready state
- ✅ System pods running (CoreDNS, etc.)
- ✅ DNS resolution working
- ✅ Pod-to-pod networking
- ✅ Storage classes available
- ✅ Namespace creation permissions
- ✅ Sufficient node resources
- ✅ Metrics server available (optional)

```bash
# Run Phase 2
make test-infra
```

### Phase 3: Baseline Testing

**Purpose**: Establish performance baselines without service mesh
**Duration**: 10-30 minutes (depending on test duration)
**Requirements**: Deployed baseline workloads

Tests:
- ✅ Deploy baseline HTTP/gRPC services
- ✅ Verify pod readiness
- ✅ Test service connectivity
- ✅ Run HTTP load tests (wrk + ab)
- ✅ Run gRPC load tests (ghz)
- ✅ Measure resource usage
- ✅ Collect latency metrics (p50, p95, p99)
- ✅ Measure throughput
- ✅ Verify error rates < 5%

```bash
# Deploy baseline workloads
make deploy-baseline

# Run baseline tests
make test-baseline
```

**Baseline Metrics Collected**:
- Average latency (ms)
- Requests per second
- CPU usage (millicores)
- Memory usage (MiB)
- Error rate (%)

### Phase 4: Service Mesh Testing

**Purpose**: Test service mesh implementations and measure overhead
**Duration**: 15-45 minutes per mesh
**Requirements**: Installed service mesh, deployed workloads

Tests:
- ✅ Verify service mesh installed
- ✅ Deploy workloads with mesh integration
- ✅ Verify sidecar injection (Istio/Linkerd)
- ✅ Verify eBPF programs loaded (Cilium)
- ✅ Test service connectivity through mesh
- ✅ Verify mTLS enabled
- ✅ Run HTTP/gRPC load tests
- ✅ Measure control plane resources
- ✅ Measure data plane resources
- ✅ Calculate overhead vs baseline

```bash
# For Istio
make install-istio
make deploy-workloads
make test-mesh-istio

# For Cilium
make install-cilium
make deploy-workloads
make test-mesh-cilium

# For Linkerd
make install-linkerd
make deploy-workloads
make test-mesh-linkerd
```

**Service Mesh Metrics Collected**:
- Latency with mesh (ms)
- Throughput with mesh (req/s)
- Control plane CPU/Memory
- Data plane CPU/Memory
- Total overhead vs baseline

### Phase 6: Comparative Analysis

**Purpose**: Compare performance across all tested meshes
**Duration**: < 5 minutes
**Requirements**: Completed baseline and mesh tests

Tests:
- ✅ Load all metrics files
- ✅ Compare latency across meshes
- ✅ Compare throughput across meshes
- ✅ Compare resource overhead
- ✅ Generate comparison tables
- ✅ Determine best performers
- ✅ Create summary report

```bash
# Run comparative analysis
make test-compare
```

**Output**:
- Latency comparison table
- Throughput comparison table
- Resource overhead table
- Best performer summary
- JSON reports in `benchmarks/results/`

### Phase 7: Stress and Edge Case Testing

**Purpose**: Verify behavior under extreme conditions
**Duration**: 30-60 minutes
**Requirements**: Deployed infrastructure and workloads

Tests:
- ✅ High concurrent connections (5x normal)
- ✅ Extended duration tests (10 minutes)
- ✅ Burst traffic patterns
- ✅ Pod failure recovery
- ✅ Service continuity during failures
- ✅ Node resource saturation
- ✅ Network policy enforcement
- ✅ mTLS enforcement
- ✅ Empty/large payload handling
- ✅ Cross-namespace access

```bash
# Run stress tests
make test-stress MESH_TYPE=istio

# Or for baseline
make test-stress MESH_TYPE=baseline
```

## Quick Start

### Prerequisites

```bash
# Install test dependencies
make test-deps

# Verify installation
python3 -m pytest --version
```

### Running Tests

**1. Pre-deployment validation (no infrastructure needed)**:
```bash
make test-validate
```

**2. Full baseline testing workflow**:
```bash
# Deploy infrastructure
make deploy-infra

# Deploy baseline workloads
make deploy-baseline

# Run all baseline tests
make test-full
```

**3. Full service mesh testing workflow (Istio example)**:
```bash
# Install Istio
make install-istio

# Deploy workloads
make deploy-workloads

# Run all Istio tests
make test-full-istio
```

**4. Comprehensive testing (all meshes)**:
```bash
make test-comprehensive
```

### Test Orchestration Script

For advanced control, use the orchestration script:

```bash
cd tests

# Run specific phase
python run_tests.py --phase=1

# Run for specific mesh
python run_tests.py --phase=all --mesh-type=cilium

# Custom test parameters
python run_tests.py \
  --phase=all \
  --mesh-type=istio \
  --test-duration=120 \
  --concurrent-connections=200 \
  --include-slow
```

**Available options**:
- `--phase`: Which phase to run (all, 1, 2, 3, 4, 6, 7, pre, infra, baseline, mesh, stress, compare)
- `--mesh-type`: Service mesh (baseline, istio, cilium, linkerd)
- `--kubeconfig`: Path to kubeconfig
- `--skip-infra`: Skip infrastructure tests
- `--test-duration`: Load test duration in seconds
- `--concurrent-connections`: Number of concurrent connections
- `--include-slow`: Include slow-running tests
- `--parallel`: Number of parallel test workers

## Test Commands

### Individual Phase Tests

```bash
make test-validate      # Phase 1: Pre-deployment
make test-infra         # Phase 2: Infrastructure
make test-baseline      # Phase 3: Baseline
make test-mesh-istio    # Phase 4: Istio
make test-mesh-cilium   # Phase 4: Cilium
make test-compare       # Phase 6: Comparative
make test-stress        # Phase 7: Stress tests
```

### Combined Tests

```bash
make test-full           # Full baseline test suite
make test-full-istio     # Full Istio test suite
make test-full-cilium    # Full Cilium test suite
make test-comprehensive  # All phases, all meshes
```

### Utility Commands

```bash
make test-quick          # Run fast tests only
make test-ci             # Run CI-friendly tests
make test-report         # Generate HTML report
make test-clean          # Clean test artifacts
```

### Custom Parameters

```bash
# Custom test duration and connections
make test-orchestrated MESH_TYPE=istio PHASE=4 TEST_DURATION=300 CONNECTIONS=500

# Specific mesh with custom phase
make test-mesh MESH_TYPE=cilium
```

## Health Checks

### Service Health Endpoints

All services include health check endpoints:

**HTTP Services**:
- `/health` - Simple health check (returns 200 OK)
- `/ready` - Readiness check
- `/metrics` - Resource metrics

**gRPC Services**:
- TCP socket check on port 9000
- gRPC health checking protocol

**Health Check Service**:
A dedicated health check service with comprehensive monitoring:

```bash
# Deploy health check service
kubectl apply -f kubernetes/workloads/health-check-service.yaml

# Access health endpoints
kubectl port-forward -n health-check svc/health-check 8080:8080

# Test endpoints
curl http://localhost:8080/health   # Basic health
curl http://localhost:8080/ready    # Readiness
curl http://localhost:8080/probe    # Comprehensive probe
curl http://localhost:8080/metrics  # Resource metrics
```

### Kubernetes Probes

All deployments include:
- **Liveness Probe**: Ensures pod is alive
- **Readiness Probe**: Ensures pod is ready to serve traffic

Example from HTTP service:
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 80
  initialDelaySeconds: 10
  periodSeconds: 5

readinessProbe:
  httpGet:
    path: /health
    port: 80
  initialDelaySeconds: 5
  periodSeconds: 3
```

## Test Results

### Result Files

All test results are stored in `benchmarks/results/`:

**Metrics Files**:
- `baseline_http_metrics.json` - Baseline HTTP performance
- `baseline_grpc_metrics.json` - Baseline gRPC performance
- `baseline_resources.json` - Baseline resource usage
- `{mesh}_http_metrics.json` - Mesh HTTP performance
- `{mesh}_grpc_metrics.json` - Mesh gRPC performance
- `{mesh}_overhead.json` - Mesh resource overhead
- `{mesh}_latency_comparison.json` - Latency comparisons

**Test Reports**:
- `test_report.html` - HTML test report
- `test_report.json` - JSON test report
- `test_run_summary.json` - Test run summary
- `test_summary.json` - Overall test summary

**Comparison Reports**:
- `latency_comparison.json` - Latency across meshes
- `best_performers.json` - Best performing mesh per metric

### Viewing Results

```bash
# Generate comprehensive report
make test-report

# View in browser
open benchmarks/results/report.html

# View JSON summary
cat benchmarks/results/test_summary.json | jq .

# View specific metrics
cat benchmarks/results/baseline_http_metrics.json | jq '.metrics'
```

### Expected Metrics

**Baseline (no mesh)**:
- Latency: 1-10ms (p50), 5-50ms (p95)
- Throughput: 1000-10000 req/s (depends on resources)
- CPU: 100-500m per pod
- Memory: 64-256Mi per pod

**With Service Mesh**:
- Latency Overhead: +10-50% (Cilium lower, Istio higher)
- Throughput: -5-20% degradation
- Control Plane: 200-1000m CPU, 500-2000Mi Memory
- Data Plane: +50-200m CPU per pod, +50-150Mi Memory per pod

## CI/CD Integration

### GitHub Actions

The repository includes a GitHub Actions workflow (`.github/workflows/test.yml`):

**Triggers**:
- Push to `main` or `develop`
- Pull requests to `main`
- Manual workflow dispatch

**Jobs**:
1. Pre-deployment tests (always run)
2. Lint and validate (always run)
3. Integration tests (manual trigger only, requires credentials)

```bash
# To trigger manually with specific mesh
gh workflow run test.yml -f mesh_type=istio
```

### Custom CI/CD

For other CI/CD systems:

```yaml
# Example GitLab CI
test:
  script:
    - make test-deps
    - make test-validate
    - make test-ci
  artifacts:
    paths:
      - benchmarks/results/
```

## Troubleshooting

### Common Issues

**1. `kubectl` not found**
```bash
# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

**2. Cannot access Kubernetes cluster**
```bash
# Verify kubeconfig
kubectl cluster-info

# Use specific kubeconfig
export KUBECONFIG=/path/to/kubeconfig
make test-infra
```

**3. Pods not ready**
```bash
# Check pod status
kubectl get pods --all-namespaces

# Check pod logs
kubectl logs -n http-benchmark <pod-name>

# Describe pod
kubectl describe pod -n http-benchmark <pod-name>
```

**4. Metrics server not available**
```bash
# These tests will be skipped automatically
# To install metrics server:
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

**5. Tests timing out**
```bash
# Increase timeout
cd tests
pytest -v --timeout=900  # 15 minutes

# Or disable timeout for debugging
pytest -v --timeout=0
```

**6. Permission errors**
```bash
# Verify RBAC permissions
kubectl auth can-i create pods --all-namespaces

# Check current context
kubectl config current-context
```

### Debug Mode

Run tests with verbose output:

```bash
# Maximum verbosity
cd tests
pytest -vv --log-cli-level=DEBUG -s

# Keep test pods for inspection
pytest -v --keep-pods  # (if implemented)
```

### Selective Testing

```bash
# Run specific test
cd tests
pytest -v test_phase1_predeployment.py::TestPreDeployment::test_terraform_installed

# Run tests matching pattern
pytest -v -k "health"

# Run tests by marker
pytest -v -m "not slow"
```

## Best Practices

1. **Always run Phase 1 first** - Validates environment before consuming resources
2. **Establish baseline** - Always test baseline before service mesh
3. **One mesh at a time** - Clean environment between mesh tests
4. **Monitor resources** - Keep an eye on cluster resources during tests
5. **Review logs** - Check logs for warnings even if tests pass
6. **Version control results** - Commit result summaries for tracking
7. **Document changes** - Note infrastructure changes that affect tests
8. **Clean up** - Run `make destroy` when done to avoid charges

## Next Steps

- Review test results in `benchmarks/results/`
- Compare mesh performance using `best_performers.json`
- Generate comprehensive report with `make test-report`
- Customize tests for your specific use case
- Integrate with your CI/CD pipeline
- Add custom test cases as needed

For more information, see:
- [README.md](../README.md) - Project overview
- [generate-report.py](../generate-report.py) - Report generation
- [conftest.py](conftest.py) - Test fixtures and configuration
