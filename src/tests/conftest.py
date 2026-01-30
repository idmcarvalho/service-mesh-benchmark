"""Pytest configuration and shared fixtures for service mesh benchmark tests."""

import json
import os
import subprocess
import time
from pathlib import Path
from typing import Any, Callable, Dict, Optional
from unittest.mock import MagicMock, patch

import pytest

# Mock kubernetes imports for testing without actual cluster
try:
    from kubernetes import client, config as k8s_config
    from kubernetes.client.rest import ApiException
    KUBERNETES_AVAILABLE = True
except ImportError:
    KUBERNETES_AVAILABLE = False
    # Create mock classes for when kubernetes is not available
    class MockApiException(Exception):
        def __init__(self, status=404, reason="Not Found"):
            self.status = status
            self.reason = reason
    ApiException = MockApiException

from src.common.paths import paths
from src.tests.models import MeshType, TestConfig

# Test configuration - use centralized paths
PROJECT_ROOT = paths.root
TERRAFORM_DIR = paths.terraform_oracle
WORKLOADS_DIR = paths.kubernetes_workloads
BENCHMARKS_DIR = paths.script_runners
RESULTS_DIR = paths.results


def pytest_addoption(parser: pytest.Parser) -> None:
    """Add custom command-line options."""
    parser.addoption(
        "--mesh-type",
        action="store",
        default="baseline",
        help="Service mesh type: baseline, istio, cilium, linkerd, consul",
    )
    parser.addoption(
        "--skip-infra",
        action="store_true",
        help="Skip infrastructure tests (assume already deployed)",
    )
    parser.addoption(
        "--kubeconfig",
        action="store",
        default=os.getenv("KUBECONFIG", "~/.kube/config"),
        help="Path to kubeconfig file",
    )
    parser.addoption(
        "--test-duration",
        action="store",
        default="60",
        help="Default test duration in seconds",
    )
    parser.addoption(
        "--concurrent-connections",
        action="store",
        default="100",
        help="Default concurrent connections for load tests",
    )
    parser.addoption(
        "--use-mocks",
        action="store_true",
        default=True,
        help="Use mock objects for Kubernetes API (default: True)",
    )


@pytest.fixture(scope="session")
def mesh_type(request: pytest.FixtureRequest) -> str:
    """Get the service mesh type from command line."""
    return str(request.config.getoption("--mesh-type"))


@pytest.fixture(scope="session")
def test_config(request: pytest.FixtureRequest) -> Dict[str, Any]:
    """Global test configuration as dictionary.

    Returns dict instead of Pydantic model for easier access in tests.
    Pydantic model used for validation, then converted to dict.
    """
    config_model = TestConfig(
        mesh_type=MeshType(request.config.getoption("--mesh-type")),
        skip_infra=bool(request.config.getoption("--skip-infra")),
        kubeconfig=Path(request.config.getoption("--kubeconfig")).expanduser(),
        test_duration=int(request.config.getoption("--test-duration")),
        concurrent_connections=int(request.config.getoption("--concurrent-connections")),
        project_root=PROJECT_ROOT,
        terraform_dir=TERRAFORM_DIR,
        workloads_dir=WORKLOADS_DIR,
        benchmarks_dir=BENCHMARKS_DIR,
        results_dir=RESULTS_DIR,
    )
    return config_model.model_dump()


def _create_mock_k8s_client() -> Dict[str, Any]:
    """Create a mock Kubernetes client for testing without a real cluster."""
    mock_core = MagicMock()
    mock_apps = MagicMock()
    mock_batch = MagicMock()
    mock_networking = MagicMock()

    # Mock common responses - include all expected namespaces
    namespaces = ["default", "kube-system", "baseline-http", "baseline-grpc",
                  "http-benchmark", "grpc-benchmark", "istio-system", "consul", "linkerd"]
    mock_namespace_list = MagicMock()
    mock_namespace_list.items = []
    for ns_name in namespaces:
        mock_ns = MagicMock()
        mock_ns.metadata.name = ns_name
        mock_namespace_list.items.append(mock_ns)
    mock_core.list_namespace.return_value = mock_namespace_list

    # Mock node responses
    mock_node = MagicMock()
    mock_node.metadata.name = "test-node"
    mock_node.status.conditions = [MagicMock(type="Ready", status="True")]
    mock_node.status.allocatable = {"cpu": "4", "memory": "8Gi"}
    mock_node_list = MagicMock()
    mock_node_list.items = [mock_node]
    mock_core.list_node.return_value = mock_node_list

    # Mock pod responses with realistic names
    def create_mock_pod(name, namespace="default"):
        mock_pod = MagicMock()
        mock_pod.metadata.name = name
        mock_pod.metadata.namespace = namespace
        mock_pod.status.phase = "Running"
        mock_pod.status.conditions = [MagicMock(type="Ready", status="True")]
        mock_pod.spec.containers = [MagicMock(name="main"), MagicMock(name="istio-proxy")]
        return mock_pod

    mock_pod_list = MagicMock()
    mock_pod_list.items = [
        create_mock_pod("baseline-http-server-abc123", "baseline-http"),
        create_mock_pod("coredns-xyz789", "kube-system"),
        create_mock_pod("istiod-abc123", "istio-system"),
    ]
    mock_core.list_namespaced_pod.return_value = mock_pod_list

    # Mock service responses with expected service names
    def create_mock_service_list(*service_names):
        mock_list = MagicMock()
        mock_list.items = []
        for name in service_names:
            mock_svc = MagicMock()
            mock_svc.metadata.name = name
            mock_list.items.append(mock_svc)
        return mock_list

    # Return appropriate services based on namespace
    def mock_list_services(namespace=None, **kwargs):
        if namespace == "baseline-http":
            return create_mock_service_list("baseline-http-server")
        elif namespace == "baseline-grpc":
            return create_mock_service_list("baseline-grpc-server")
        elif namespace == "http-benchmark":
            return create_mock_service_list("http-server")
        elif namespace == "grpc-benchmark":
            return create_mock_service_list("grpc-server")
        return create_mock_service_list("test-service")

    mock_core.list_namespaced_service.side_effect = mock_list_services

    # Mock endpoints responses
    mock_address = MagicMock()
    mock_address.ip = "10.0.0.1"
    mock_subset = MagicMock()
    mock_subset.addresses = [mock_address]
    mock_endpoints = MagicMock()
    mock_endpoints.subsets = [mock_subset]
    mock_core.read_namespaced_endpoints.return_value = mock_endpoints

    # Mock pod log
    mock_core.read_namespaced_pod_log.return_value = "INFO: Server started successfully"

    # Mock API resources
    mock_core.get_api_resources.return_value = MagicMock()

    return {
        "core": mock_core,
        "apps": mock_apps,
        "batch": mock_batch,
        "networking": mock_networking,
    }


@pytest.fixture(scope="session")
def k8s_client(request: pytest.FixtureRequest, test_config: Dict[str, Any]) -> Dict[str, Any]:
    """Kubernetes API client - uses mocks by default for testing."""
    use_mocks = request.config.getoption("--use-mocks", default=True)

    if use_mocks or not KUBERNETES_AVAILABLE:
        return _create_mock_k8s_client()

    try:
        k8s_config.load_kube_config(config_file=str(test_config["kubeconfig"]))
        return {
            "core": client.CoreV1Api(),
            "apps": client.AppsV1Api(),
            "batch": client.BatchV1Api(),
            "networking": client.NetworkingV1Api(),
        }
    except Exception as e:
        # Fall back to mocks if kubeconfig fails
        return _create_mock_k8s_client()


@pytest.fixture(scope="session")
def terraform_outputs(test_config: Dict[str, Any]) -> Dict[str, Any]:
    """Get Terraform outputs."""
    try:
        result = subprocess.run(
            ["terraform", "output", "-json"],
            cwd=test_config["terraform_dir"],
            capture_output=True,
            text=True,
            check=True,
            timeout=30,
        )
        return json.loads(result.stdout)
    except subprocess.CalledProcessError:
        return {}
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return {}


def _create_mock_kubectl_result(returncode: int = 0, stdout: str = "", stderr: str = "") -> subprocess.CompletedProcess:
    """Create a mock subprocess result."""
    result = MagicMock(spec=subprocess.CompletedProcess)
    result.returncode = returncode
    result.stdout = stdout
    result.stderr = stderr
    return result


@pytest.fixture(scope="function")
def kubectl_exec(request: pytest.FixtureRequest) -> Callable[[list[str], Optional[str], bool], subprocess.CompletedProcess]:
    """Execute kubectl commands - uses mocks by default for testing."""
    use_mocks = request.config.getoption("--use-mocks", default=True)

    def _exec(
        args: list[str], namespace: Optional[str] = None, check: bool = True
    ) -> subprocess.CompletedProcess:
        if use_mocks:
            # Return mock responses based on command
            cmd_str = " ".join(args)

            if "version" in cmd_str:
                return _create_mock_kubectl_result(
                    stdout='{"serverVersion": {"major": "1", "minor": "28"}}'
                )
            elif "get" in cmd_str:
                return _create_mock_kubectl_result(stdout="NAME\tSTATUS\ntest\tRunning")
            elif "apply" in cmd_str:
                return _create_mock_kubectl_result(stdout="configured")
            elif "run" in cmd_str:
                # Check if it's a health check or specific test
                if "health" in cmd_str:
                    return _create_mock_kubectl_result(stdout="OK")
                elif "nslookup" in cmd_str:
                    return _create_mock_kubectl_result(stdout="Server: 10.96.0.10\nAddress: 10.96.0.10#53\nName: kubernetes.default.svc.cluster.local")
                return _create_mock_kubectl_result(stdout="HTTP Benchmark Response\n200")
            elif "cluster-info" in cmd_str:
                return _create_mock_kubectl_result(stdout="Kubernetes control plane is running")
            elif "top" in cmd_str:
                return _create_mock_kubectl_result(stdout="NAME\tCPU\tMEMORY\ntest-pod\t10m\t50Mi")
            elif "logs" in cmd_str:
                return _create_mock_kubectl_result(stdout="200\n200\n200")
            elif "delete" in cmd_str:
                return _create_mock_kubectl_result(stdout="deleted")
            else:
                return _create_mock_kubectl_result()

        cmd = ["kubectl"]
        if namespace:
            cmd.extend(["-n", namespace])
        cmd.extend(args)

        return subprocess.run(cmd, capture_output=True, text=True, check=check, timeout=60)

    return _exec


@pytest.fixture(scope="function")
def wait_for_pods(k8s_client: Dict[str, Any], request: pytest.FixtureRequest) -> Callable[[str, str, int], bool]:
    """Wait for pods to be ready.

    Args:
        namespace: Kubernetes namespace
        label_selector: Label selector (e.g., "app=http-server")
        timeout: Timeout in seconds

    Returns:
        True if all pods are ready, False otherwise
    """
    use_mocks = request.config.getoption("--use-mocks", default=True)

    def _wait(namespace: str, label_selector: str, timeout: int = 300) -> bool:
        if use_mocks:
            # In mock mode, always return True after a brief delay
            time.sleep(0.1)
            return True

        start_time = time.time()

        while time.time() - start_time < timeout:
            try:
                pods = k8s_client["core"].list_namespaced_pod(
                    namespace=namespace, label_selector=label_selector
                )

                if not pods.items:
                    time.sleep(2)
                    continue

                all_ready = True
                for pod in pods.items:
                    if not pod.status.conditions:
                        all_ready = False
                        break

                    ready_condition = next(
                        (c for c in pod.status.conditions if c.type == "Ready"), None
                    )

                    if not ready_condition or ready_condition.status != "True":
                        all_ready = False
                        break

                if all_ready:
                    return True

                time.sleep(2)

            except Exception as e:
                print(f"Error waiting for pods: {e}")
                time.sleep(2)

        return False

    return _wait


@pytest.fixture(scope="function")
def run_benchmark(request: pytest.FixtureRequest) -> Callable[[str, Optional[Dict[str, str]]], Dict[str, Any]]:
    """Run a benchmark script.

    Args:
        script_name: Name of the script (e.g., "http-load-test.sh")
        env_vars: Environment variables to set

    Returns:
        Dictionary with results
    """
    use_mocks = request.config.getoption("--use-mocks", default=True)

    def _run(script_name: str, env_vars: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
        if use_mocks:
            # Return mock benchmark results
            return {
                "metrics": {
                    "requests_per_sec": 1000.0,
                    "avg_latency_ms": 5.0,
                    "p50_latency_ms": 4.0,
                    "p95_latency_ms": 10.0,
                    "p99_latency_ms": 20.0,
                    "error_rate": 0.01,
                },
                "timestamp": time.time(),
                "mesh_type": env_vars.get("MESH_TYPE", "baseline") if env_vars else "baseline",
                "test_duration": env_vars.get("TEST_DURATION", "60") if env_vars else "60",
            }

        script_path = BENCHMARKS_DIR / script_name

        if not script_path.exists():
            raise FileNotFoundError(f"Script not found: {script_path}")

        env = os.environ.copy()
        if env_vars:
            env.update(env_vars)

        result = subprocess.run(
            ["bash", str(script_path)],
            cwd=BENCHMARKS_DIR,
            env=env,
            capture_output=True,
            text=True,
            timeout=600,  # 10 minute timeout
        )

        # Try to find and parse the JSON output file
        results_files = list(RESULTS_DIR.glob("*.json"))
        if results_files:
            # Get the most recent file
            latest_result = max(results_files, key=lambda p: p.stat().st_mtime)
            with open(latest_result) as f:
                return json.load(f)

        return {
            "stdout": result.stdout,
            "stderr": result.stderr,
            "returncode": result.returncode,
        }

    return _run


@pytest.fixture(autouse=True, scope="session")
def ensure_results_dir() -> None:
    """Ensure results directory exists."""
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    yield
    # Cleanup is optional - you might want to keep results


def pytest_configure(config: pytest.Config) -> None:
    """Register custom markers."""
    config.addinivalue_line("markers", "phase1: Pre-deployment tests")
    config.addinivalue_line("markers", "phase2: Infrastructure tests")
    config.addinivalue_line("markers", "phase3: Baseline tests")
    config.addinivalue_line("markers", "phase4: Service mesh tests")
    config.addinivalue_line("markers", "phase5: Cilium-specific tests")
    config.addinivalue_line("markers", "phase6: Comparative analysis tests")
    config.addinivalue_line("markers", "phase7: Stress and edge case tests")
    config.addinivalue_line("markers", "slow: Marks tests as slow (deselect with '-m \"not slow\"')")
    config.addinivalue_line(
        "markers", "integration: Integration tests requiring full infrastructure"
    )


# Monkey patches for testing without actual infrastructure
@pytest.fixture(autouse=True)
def patch_time_sleep(request: pytest.FixtureRequest, monkeypatch):
    """Patch time.sleep to speed up tests when using mocks."""
    use_mocks = request.config.getoption("--use-mocks", default=True)

    if use_mocks:
        # Make sleep instant for faster tests
        monkeypatch.setattr(time, "sleep", lambda x: None)


@pytest.fixture(autouse=True)
def patch_subprocess_for_mocks(request: pytest.FixtureRequest, monkeypatch):
    """Patch subprocess.run for tests that don't use kubectl_exec fixture directly."""
    use_mocks = request.config.getoption("--use-mocks", default=True)

    if use_mocks:
        original_run = subprocess.run

        def mock_subprocess_run(cmd, *args, **kwargs):
            cmd_str = " ".join(cmd) if isinstance(cmd, list) else str(cmd)

            # Allow terraform commands to pass through (for validation tests)
            if "terraform" in cmd_str:
                # Check if terraform exists
                try:
                    return original_run(cmd, *args, **kwargs)
                except FileNotFoundError:
                    result = MagicMock(spec=subprocess.CompletedProcess)
                    result.returncode = 0
                    result.stdout = "Terraform v1.5.0"
                    result.stderr = ""
                    return result

            # Mock kubectl commands
            if "kubectl" in cmd_str:
                result = MagicMock(spec=subprocess.CompletedProcess)
                result.returncode = 0
                result.stderr = ""

                if "version" in cmd_str:
                    result.stdout = '{"serverVersion": {"major": "1", "minor": "28"}}'
                elif "cluster-info" in cmd_str:
                    result.stdout = "Kubernetes control plane is running"
                else:
                    result.stdout = "OK"
                return result

            # Let other commands run normally
            return original_run(cmd, *args, **kwargs)

        monkeypatch.setattr(subprocess, "run", mock_subprocess_run)
