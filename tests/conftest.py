"""Pytest configuration and shared fixtures for service mesh benchmark tests."""

import json
import os
import subprocess
import time
from pathlib import Path
from typing import Any, Callable, Dict, Optional

import pytest
from kubernetes import client, config as k8s_config

from tests.models import MeshType, TestConfig

# Test configuration
PROJECT_ROOT = Path(__file__).parent.parent
TERRAFORM_DIR = PROJECT_ROOT / "terraform" / "oracle-cloud"
WORKLOADS_DIR = PROJECT_ROOT / "kubernetes" / "workloads"
BENCHMARKS_DIR = PROJECT_ROOT / "benchmarks" / "scripts"
RESULTS_DIR = PROJECT_ROOT / "benchmarks" / "results"


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


@pytest.fixture(scope="session")
def mesh_type(request: pytest.FixtureRequest) -> str:
    """Get the service mesh type from command line."""
    return str(request.config.getoption("--mesh-type"))


@pytest.fixture(scope="session")
def test_config(request: pytest.FixtureRequest) -> TestConfig:
    """Global test configuration using Pydantic model."""
    return TestConfig(
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


@pytest.fixture(scope="session")
def k8s_client(test_config: TestConfig) -> Dict[str, Any]:
    """Kubernetes API client."""
    try:
        k8s_config.load_kube_config(config_file=str(test_config.kubeconfig))
        return {
            "core": client.CoreV1Api(),
            "apps": client.AppsV1Api(),
            "batch": client.BatchV1Api(),
            "networking": client.NetworkingV1Api(),
        }
    except Exception as e:
        pytest.skip(f"Cannot load kubeconfig: {e}")


@pytest.fixture(scope="session")
def terraform_outputs(test_config: TestConfig) -> Dict[str, Any]:
    """Get Terraform outputs."""
    try:
        result = subprocess.run(
            ["terraform", "output", "-json"],
            cwd=test_config.terraform_dir,
            capture_output=True,
            text=True,
            check=True,
            timeout=30,
        )
        return json.loads(result.stdout)
    except subprocess.CalledProcessError:
        return {}
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pytest.skip("Terraform not found or timed out")


@pytest.fixture(scope="function")
def kubectl_exec() -> Callable[[list[str], Optional[str], bool], subprocess.CompletedProcess]:
    """Execute kubectl commands."""

    def _exec(
        args: list[str], namespace: Optional[str] = None, check: bool = True
    ) -> subprocess.CompletedProcess:
        cmd = ["kubectl"]
        if namespace:
            cmd.extend(["-n", namespace])
        cmd.extend(args)

        return subprocess.run(cmd, capture_output=True, text=True, check=check, timeout=60)

    return _exec


@pytest.fixture(scope="function")
def wait_for_pods(k8s_client: Dict[str, Any]) -> Callable[[str, str, int], bool]:
    """Wait for pods to be ready.

    Args:
        namespace: Kubernetes namespace
        label_selector: Label selector (e.g., "app=http-server")
        timeout: Timeout in seconds

    Returns:
        True if all pods are ready, False otherwise
    """

    def _wait(namespace: str, label_selector: str, timeout: int = 300) -> bool:
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
def run_benchmark() -> Callable[[str, Optional[Dict[str, str]]], Dict[str, Any]]:
    """Run a benchmark script.

    Args:
        script_name: Name of the script (e.g., "http-load-test.sh")
        env_vars: Environment variables to set

    Returns:
        Dictionary with results
    """

    def _run(script_name: str, env_vars: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
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
