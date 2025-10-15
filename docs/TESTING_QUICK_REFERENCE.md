# Testing Quick Reference Guide

## Installation

```bash
# Install test dependencies
make test-deps
```

## Common Commands

### Quick Tests

```bash
make test-validate     # Phase 1: Validation (< 5 min)
make test-quick        # Fast tests only
make test-ci           # CI-friendly tests
```

### Full Test Suites

```bash
make test-full              # Baseline (complete)
make test-full-istio        # Istio (complete)
make test-full-cilium       # Cilium (complete)
make test-comprehensive     # All phases, all meshes
```

### Individual Phases

```bash
make test-validate      # Phase 1: Pre-deployment
make test-infra         # Phase 2: Infrastructure
make test-baseline      # Phase 3: Baseline
make test-mesh-istio    # Phase 4: Istio
make test-mesh-cilium   # Phase 4: Cilium
make test-compare       # Phase 6: Comparative
make test-stress        # Phase 7: Stress
```

### Custom Parameters

```bash
# Custom mesh and phase
make test-orchestrated MESH_TYPE=istio PHASE=4

# Custom test duration and connections
make test-orchestrated \
  MESH_TYPE=cilium \
  PHASE=all \
  TEST_DURATION=300 \
  CONNECTIONS=500
```

## Testing Workflow

### 1. Baseline Testing

```bash
# Deploy
make deploy-infra
make deploy-baseline

# Test
make test-validate
make test-infra
make test-baseline

# Results in: benchmarks/results/baseline_*.json
```

### 2. Istio Testing

```bash
# Deploy
make install-istio
make deploy-workloads

# Test
make test-mesh-istio

# Results in: benchmarks/results/istio_*.json
```

### 3. Cilium Testing

```bash
# Clean previous mesh
make clean-workloads
# Uninstall previous mesh manually

# Deploy
make install-cilium
make deploy-workloads

# Test
make test-mesh-cilium

# Results in: benchmarks/results/cilium_*.json
```

### 4. Compare Results

```bash
make test-compare

# View results
cat benchmarks/results/best_performers.json
make test-report
open benchmarks/results/report.html
```

## Direct Pytest Commands

### By Phase

```bash
cd tests

pytest -v -m phase1                           # Pre-deployment
pytest -v -m phase2                           # Infrastructure
pytest -v -m phase3 --mesh-type=baseline      # Baseline
pytest -v -m phase4 --mesh-type=istio         # Istio
pytest -v -m phase6                           # Comparative
pytest -v -m phase7 --mesh-type=baseline      # Stress
```

### By Category

```bash
pytest -v -m "not slow"                       # Exclude slow tests
pytest -v -m integration                       # Integration tests only
pytest -v -m "phase2 and not slow"            # Combined markers
```

### Specific Tests

```bash
# Single file
pytest -v test_phase1_predeployment.py

# Single class
pytest -v test_phase2_infrastructure.py::TestInfrastructure

# Single test
pytest -v test_phase1_predeployment.py::TestPreDeployment::test_terraform_installed

# Pattern matching
pytest -v -k "health"
```

## Orchestration Script

```bash
cd tests

# All phases for baseline
python run_tests.py --phase=all --mesh-type=baseline

# Specific phase
python run_tests.py --phase=infra

# With parameters
python run_tests.py \
  --phase=all \
  --mesh-type=istio \
  --test-duration=120 \
  --concurrent-connections=200 \
  --include-slow

# Parallel execution
python run_tests.py --phase=all --parallel=4
```

## Results & Reports

### View Results

```bash
# List results
ls -lh benchmarks/results/

# View metrics (with jq)
cat benchmarks/results/baseline_http_metrics.json | jq .
cat benchmarks/results/istio_http_metrics.json | jq '.metrics'
cat benchmarks/results/best_performers.json | jq .

# View test report
open benchmarks/results/test_report.html
```

### Generate Reports

```bash
make test-report
make generate-report
```

## Expected Metrics

### Baseline

| Metric | Expected Value |
|--------|---------------|
| Latency (p50) | 1-10ms |
| Latency (p95) | 5-50ms |
| Throughput | 1000-10000 req/s |
| CPU per pod | 100-500m |
| Memory per pod | 64-256Mi |

### Service Mesh Overhead

| Mesh | Latency Overhead | Throughput Impact | CPU Overhead | Memory Overhead |
|------|-----------------|-------------------|--------------|-----------------|
| Istio | +20-40% | -10-20% | +500-1000m | +500-1500Mi |
| Cilium | +5-15% | -5-10% | +200-500m | +200-800Mi |
| Linkerd | +10-25% | -5-15% | +300-700m | +300-1000Mi |

*Values depend on workload and cluster resources*

## Health Checks

```bash
# Deploy health check service
kubectl apply -f kubernetes/workloads/health-check-service.yaml

# Port forward
kubectl port-forward -n health-check svc/health-check 8080:8080

# Test endpoints
curl http://localhost:8080/health
curl http://localhost:8080/ready
curl http://localhost:8080/probe
curl http://localhost:8080/metrics
```

## Troubleshooting

### Common Fixes

```bash
# Kubeconfig not found
export KUBECONFIG=/path/to/kubeconfig

# Pods not ready
kubectl get pods --all-namespaces
kubectl describe pod -n http-benchmark <pod-name>

# Tests timing out
pytest -v --timeout=900

# Permission errors
kubectl auth can-i create pods --all-namespaces

# Clean artifacts
make test-clean
```

### Debug Mode

```bash
# Verbose output
pytest -vv --log-cli-level=DEBUG -s

# Single test debug
pytest -vv -s test_phase1_predeployment.py::TestPreDeployment::test_terraform_installed
```

## File Locations

```
tests/
├── conftest.py                    # Fixtures
├── pytest.ini                     # Config
├── requirements.txt               # Dependencies
├── run_tests.py                   # Orchestration
├── test_phase1_predeployment.py  # Phase 1
├── test_phase2_infrastructure.py  # Phase 2
├── test_phase3_baseline.py        # Phase 3
├── test_phase4_servicemesh.py     # Phase 4
├── test_phase6_comparative.py     # Phase 6
└── test_phase7_stress.py          # Phase 7

benchmarks/results/
├── test_report.html               # HTML report
├── test_report.json               # JSON report
├── baseline_*.json                # Baseline metrics
├── istio_*.json                   # Istio metrics
├── cilium_*.json                  # Cilium metrics
├── *_comparison.json              # Comparisons
└── best_performers.json           # Best results
```

## CI/CD

```bash
# GitHub Actions
# Runs on push/PR automatically
# See: .github/workflows/test.yml

# Manual trigger
gh workflow run test.yml -f mesh_type=istio
```

## Tips

1. **Always start with Phase 1** - catches issues early
2. **Run baseline first** - establishes comparison point
3. **One mesh at a time** - clean environment between tests
4. **Monitor resources** - `kubectl top nodes/pods`
5. **Check logs** - even when tests pass
6. **Save results** - commit summary JSONs to track over time
7. **Use quick tests** - during development
8. **Run comprehensive** - before release/merge

## Cheat Sheet

| What | Command |
|------|---------|
| Install deps | `make test-deps` |
| Quick validation | `make test-validate` |
| Full baseline | `make test-full` |
| Full Istio | `make test-full-istio` |
| Full Cilium | `make test-full-cilium` |
| Everything | `make test-comprehensive` |
| Compare results | `make test-compare` |
| Generate report | `make test-report` |
| Clean results | `make test-clean` |
| View help | `make help` |

## Support

- 📖 [Full Testing Guide](TESTING.md)
- 📖 [Tests README](../tests/README.md)
- 📖 [Project README](../README.md)
- 🐛 [Report Issues](https://github.com/anthropics/claude-code/issues)
