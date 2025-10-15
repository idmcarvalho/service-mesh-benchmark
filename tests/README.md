# Service Mesh Benchmark Tests

Comprehensive pytest-based testing framework for service mesh benchmarking.

## Quick Start

```bash
# Install dependencies (using UV for faster installation)
# Install UV: curl -LsSf https://astral.sh/uv/install.sh | sh
uv pip install -r requirements.txt

# Or use traditional pip
pip install -r requirements.txt

# Run pre-deployment validation (no infrastructure needed)
pytest -v -m phase1

# Run infrastructure tests (requires deployed cluster)
pytest -v -m phase2 --kubeconfig=/path/to/kubeconfig

# Run baseline tests
pytest -v -m phase3 --mesh-type=baseline

# Run service mesh tests
pytest -v -m phase4 --mesh-type=istio

# Run all tests for a specific mesh
python run_tests.py --phase=all --mesh-type=cilium
```

## Test Phases

| Phase | Description | Duration | Requirements |
|-------|-------------|----------|--------------|
| 1 | Pre-deployment validation | < 5 min | None |
| 2 | Infrastructure verification | 5-10 min | Deployed cluster |
| 3 | Baseline performance | 10-30 min | Baseline workloads |
| 4 | Service mesh testing | 15-45 min | Service mesh + workloads |
| 6 | Comparative analysis | < 5 min | Completed tests |
| 7 | Stress & edge cases | 30-60 min | Deployed infrastructure |

## Test Files

- `conftest.py` - Shared fixtures and configuration
- `test_phase1_predeployment.py` - Pre-deployment validation
- `test_phase2_infrastructure.py` - Infrastructure tests
- `test_phase3_baseline.py` - Baseline performance tests
- `test_phase4_servicemesh.py` - Service mesh tests
- `test_phase6_comparative.py` - Comparative analysis
- `test_phase7_stress.py` - Stress tests
- `run_tests.py` - Test orchestration script
- `pytest.ini` - Pytest configuration

## Command-Line Options

### Pytest Options

```bash
# Specific mesh type
pytest -v --mesh-type=istio

# Custom kubeconfig
pytest -v --kubeconfig=/path/to/config

# Skip infrastructure tests
pytest -v --skip-infra

# Custom test parameters
pytest -v --test-duration=120 --concurrent-connections=200

# Exclude slow tests
pytest -v -m "not slow"

# Run tests in parallel
pytest -v -n 4
```

### Orchestration Script Options

```bash
python run_tests.py [options]

Options:
  --phase PHASE         Test phase: all, 1, 2, 3, 4, 6, 7, pre, infra, baseline, mesh, stress, compare
  --mesh-type MESH      Service mesh: baseline, istio, cilium, linkerd
  --kubeconfig PATH     Path to kubeconfig file
  --skip-infra          Skip infrastructure tests
  --test-duration N     Test duration in seconds (default: 60)
  --concurrent-connections N  Concurrent connections (default: 100)
  --include-slow        Include slow tests
  --parallel N          Number of parallel workers
```

## Examples

### Basic Testing Workflow

```bash
# 1. Validate environment
pytest -v -m phase1

# 2. Verify infrastructure
pytest -v -m phase2

# 3. Test baseline
pytest -v -m phase3 --mesh-type=baseline --test-duration=60

# 4. Test Istio
pytest -v -m phase4 --mesh-type=istio --test-duration=60

# 5. Compare results
pytest -v -m phase6
```

### Advanced Usage

```bash
# Run only fast tests
pytest -v -m "not slow"

# Run specific test class
pytest -v test_phase2_infrastructure.py::TestInfrastructure

# Run with maximum verbosity
pytest -vv --log-cli-level=DEBUG

# Generate HTML report
pytest -v --html=report.html --self-contained-html

# Run tests matching pattern
pytest -v -k "health"
```

### Orchestrated Testing

```bash
# Complete baseline test suite
python run_tests.py --phase=all --mesh-type=baseline

# Istio with custom parameters
python run_tests.py \
  --phase=all \
  --mesh-type=istio \
  --test-duration=300 \
  --concurrent-connections=500 \
  --include-slow

# Just stress tests
python run_tests.py --phase=stress --mesh-type=cilium
```

## Test Results

Results are saved to `../benchmarks/results/`:

- `test_report.html` - HTML test report
- `test_report.json` - JSON test report
- `*_metrics.json` - Performance metrics
- `*_overhead.json` - Resource overhead
- `*_comparison.json` - Comparison reports

## Fixtures

Key pytest fixtures available in all tests:

### Session-scoped Fixtures

- `test_config` - Global configuration dict
- `mesh_type` - Current service mesh type
- `k8s_client` - Kubernetes API client
- `terraform_outputs` - Terraform output values

### Function-scoped Fixtures

- `kubectl_exec` - Execute kubectl commands
- `wait_for_pods` - Wait for pods to be ready
- `run_benchmark` - Run benchmark scripts

### Example Usage

```python
def test_example(k8s_client, wait_for_pods, kubectl_exec):
    # Wait for pods
    ready = wait_for_pods("http-benchmark", "app=http-server", timeout=300)
    assert ready

    # Execute kubectl command
    result = kubectl_exec(["get", "pods", "-n", "http-benchmark"])
    assert result.returncode == 0

    # Use Kubernetes API
    pods = k8s_client["core"].list_namespaced_pod("http-benchmark")
    assert len(pods.items) > 0
```

## Markers

Use markers to select specific test categories:

```bash
# Pre-deployment tests
pytest -v -m phase1

# Integration tests
pytest -v -m integration

# Exclude slow tests
pytest -v -m "not slow"

# Multiple markers
pytest -v -m "phase2 and not slow"
```

Available markers:
- `phase1` - Pre-deployment validation
- `phase2` - Infrastructure tests
- `phase3` - Baseline tests
- `phase4` - Service mesh tests
- `phase6` - Comparative analysis
- `phase7` - Stress tests
- `slow` - Long-running tests
- `integration` - Requires full infrastructure

## Configuration

### Environment Variables

```bash
# Kubeconfig location
export KUBECONFIG=/path/to/kubeconfig

# Test parameters
export TEST_DURATION=120
export CONCURRENT_CONNECTIONS=200
```

### pytest.ini

Customize test behavior in `pytest.ini`:

```ini
[pytest]
addopts = -v --strict-markers
timeout = 600
log_cli = true
log_cli_level = INFO
```

## Troubleshooting

### Common Issues

**Tests can't find kubeconfig**:
```bash
pytest -v --kubeconfig=/path/to/config
# or
export KUBECONFIG=/path/to/config
```

**Pods not ready in time**:
```bash
# Increase timeout in test or skip
pytest -v --timeout=900
```

**Import errors**:
```bash
# Reinstall dependencies
uv pip install -r requirements.txt
# or
pip install -r requirements.txt
```

**Permission errors**:
```bash
# Verify kubectl access
kubectl auth can-i create pods --all-namespaces
```

### Debug Mode

```bash
# Verbose output with debug logs
pytest -vv --log-cli-level=DEBUG -s

# Run single test for debugging
pytest -v test_phase1_predeployment.py::TestPreDeployment::test_terraform_installed
```

## Contributing

When adding new tests:

1. Follow existing test structure
2. Use appropriate markers (`@pytest.mark.phaseN`)
3. Add docstrings to test functions
4. Use shared fixtures from `conftest.py`
5. Handle errors gracefully with proper assertions
6. Add tests to appropriate phase file

Example test:

```python
import pytest

@pytest.mark.phase2
@pytest.mark.integration
class TestMyFeature:
    """Test my new feature"""

    def test_feature_works(self, k8s_client):
        """Verify feature works correctly"""
        # Test implementation
        result = do_something()
        assert result is not None
```

## CI/CD Integration

### GitHub Actions

Tests run automatically on push/PR. See `.github/workflows/test.yml`.

### Custom CI

```yaml
# Example for other CI systems
test:
  script:
    - curl -LsSf https://astral.sh/uv/install.sh | sh
    - uv pip install -r tests/requirements.txt
    - pytest -v -m phase1
  artifacts:
    paths:
      - benchmarks/results/
```

## Further Documentation

- [Main Testing Guide](../docs/TESTING.md) - Comprehensive documentation
- [Project README](../README.md) - Project overview
- [conftest.py](conftest.py) - Fixture implementation details

## Support

For issues or questions:
- Check logs: `pytest -vv --log-cli-level=DEBUG`
- Review test results: `../benchmarks/results/test_report.html`
- See troubleshooting guide: [TESTING.md](../docs/TESTING.md#troubleshooting)
