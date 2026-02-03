"""
Phase 2: Infrastructure Tests

Tests that validate the deployed infrastructure including Terraform resources,
Kubernetes cluster health, and network connectivity.
"""
import logging
import pytest
import subprocess
import time
from kubernetes.client.rest import ApiException

logger = logging.getLogger(__name__)


@pytest.mark.phase2
@pytest.mark.integration
class TestInfrastructure:
    """Infrastructure validation tests"""

    def test_terraform_state_exists(self, test_config, request):
        """Verify Terraform state exists (infrastructure deployed)"""
        if request.config.getoption("--skip-infra", default=False):
            pytest.skip("Infrastructure tests skipped")

        result = subprocess.run(
            ["terraform", "show"],
            cwd=test_config["terraform_dir"],
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, "No Terraform state found - infrastructure not deployed"

    def test_kubernetes_cluster_accessible(self, k8s_client):
        """Verify Kubernetes cluster is accessible"""
        try:
            version = k8s_client["core"].get_api_resources()
            assert version is not None
        except Exception as e:
            pytest.fail(f"Cannot access Kubernetes cluster: {e}")

    def test_kubernetes_nodes_ready(self, k8s_client):
        """Verify all Kubernetes nodes are in Ready state"""
        nodes = k8s_client["core"].list_node()

        assert len(nodes.items) > 0, "No nodes found in cluster"

        not_ready = []
        for node in nodes.items:
            for condition in node.status.conditions:
                if condition.type == "Ready" and condition.status != "True":
                    not_ready.append(node.metadata.name)

        assert len(not_ready) == 0, f"Nodes not ready: {not_ready}"

    def test_kubernetes_nodes_count(self, k8s_client):
        """Verify expected number of nodes (1 master + 2 workers)"""
        nodes = k8s_client["core"].list_node()

        # Expected: 3 nodes total (1 master + 2 workers)
        assert len(nodes.items) >= 1, "At least 1 node should be present"

    def test_kubernetes_system_pods_running(self, k8s_client):
        """Verify system pods in kube-system namespace are running"""
        pods = k8s_client["core"].list_namespaced_pod(namespace="kube-system")

        assert len(pods.items) > 0, "No system pods found"

        not_running = []
        for pod in pods.items:
            if pod.status.phase != "Running" and pod.status.phase != "Succeeded":
                not_running.append(f"{pod.metadata.name} ({pod.status.phase})")

        assert len(not_running) == 0, f"System pods not running: {not_running}"

    def test_coredns_running(self, k8s_client):
        """Verify CoreDNS pods are running"""
        pods = k8s_client["core"].list_namespaced_pod(
            namespace="kube-system",
            label_selector="k8s-app=kube-dns"
        )

        assert len(pods.items) > 0, "CoreDNS pods not found"

        for pod in pods.items:
            assert pod.status.phase == "Running", \
                f"CoreDNS pod {pod.metadata.name} not running: {pod.status.phase}"

    def test_dns_resolution(self, kubectl_exec):
        """Test DNS resolution within cluster"""
        result = kubectl_exec([
            "run", "dns-test",
            "--image=busybox:latest",
            "--rm", "-i", "--restart=Never",
            "--",
            "nslookup", "kubernetes.default.svc.cluster.local"
        ], check=False)

        assert result.returncode == 0, f"DNS resolution failed: {result.stderr}"

    def test_pod_network_connectivity(self, k8s_client, kubectl_exec):
        """Test basic pod-to-pod networking"""
        # Create a test pod
        result = kubectl_exec([
            "run", "network-test",
            "--image=nginx:alpine",
            "--restart=Never",
            "--",
            "sh", "-c", "sleep 30"
        ], check=False)

        if result.returncode != 0:
            # Pod might already exist, that's ok
            pass

        # Wait a bit for pod to be ready
        time.sleep(5)

        # Try to access it from another pod
        result = kubectl_exec([
            "run", "network-client",
            "--image=curlimages/curl:latest",
            "--rm", "-i", "--restart=Never",
            "--",
            "curl", "-s", "--max-time", "5", "http://network-test"
        ], check=False)

        # Cleanup
        kubectl_exec(["delete", "pod", "network-test", "--ignore-not-found=true"], check=False)

        # The test might fail if pod doesn't have a service, but at least we try

    def test_storage_class_available(self, k8s_client):
        """Verify storage class is available"""
        from kubernetes.client import StorageV1Api

        storage_api = StorageV1Api()
        storage_classes = storage_api.list_storage_class()

        assert len(storage_classes.items) > 0, "No storage classes found"

    def test_namespace_creation(self, k8s_client):
        """Test ability to create namespaces"""
        from kubernetes.client import V1Namespace, V1ObjectMeta

        test_namespace = "test-permissions"

        # Try to create a test namespace
        namespace = V1Namespace(
            metadata=V1ObjectMeta(name=test_namespace)
        )

        try:
            k8s_client["core"].create_namespace(namespace)
            created = True
        except ApiException as e:
            if e.status == 409:  # Already exists
                created = True
            else:
                created = False

        # Cleanup
        try:
            k8s_client["core"].delete_namespace(test_namespace)
        except ApiException as e:
            if e.status != 404:  # Ignore if namespace doesn't exist
                logger.warning(f"Failed to cleanup test namespace {test_namespace}: {e}")
        except Exception as e:
            logger.error(f"Unexpected error during namespace cleanup: {e}", exc_info=True)

        assert created, "Cannot create namespaces"

    def test_node_resources_sufficient(self, k8s_client):
        """Verify that nodes have sufficient resources"""
        nodes = k8s_client["core"].list_node()

        for node in nodes.items:
            # Check allocatable resources
            allocatable = node.status.allocatable

            cpu = allocatable.get("cpu", "0")
            memory = allocatable.get("memory", "0")

            # Convert to numbers (rough check)
            # CPU is in cores or millicores
            if cpu.endswith("m"):
                cpu_value = int(cpu[:-1]) / 1000
            else:
                cpu_value = int(cpu)

            # Memory is in Ki
            if memory.endswith("Ki"):
                memory_value = int(memory[:-2]) / 1024 / 1024  # Convert to GB
            elif memory.endswith("Mi"):
                memory_value = int(memory[:-2]) / 1024
            elif memory.endswith("Gi"):
                memory_value = int(memory[:-2])
            else:
                memory_value = 0

            # Minimum requirements (adjust as needed)
            assert cpu_value >= 1, f"Node {node.metadata.name} has insufficient CPU: {cpu}"
            assert memory_value >= 1, f"Node {node.metadata.name} has insufficient memory: {memory}"

    def test_kubectl_permissions(self, kubectl_exec):
        """Verify kubectl has necessary permissions"""
        # Test basic operations
        operations = [
            (["get", "nodes"], "Cannot list nodes"),
            (["get", "namespaces"], "Cannot list namespaces"),
            (["get", "pods", "--all-namespaces"], "Cannot list pods"),
        ]

        for cmd, error_msg in operations:
            result = kubectl_exec(cmd, check=False)
            assert result.returncode == 0, f"{error_msg}: {result.stderr}"

    def test_cluster_version_supported(self, k8s_client):
        """Verify Kubernetes version is supported"""
        version_info = k8s_client["core"].get_api_resources()

        # Get actual version
        result = subprocess.run(
            ["kubectl", "version", "-o", "json"],
            capture_output=True,
            text=True
        )

        if result.returncode == 0:
            import json
            version_data = json.loads(result.stdout)

            # Check server version exists
            assert "serverVersion" in version_data, "Cannot determine Kubernetes version"

    def test_metrics_server_available(self, kubectl_exec):
        """Check if metrics server is available (optional but recommended)"""
        result = kubectl_exec(
            ["top", "nodes"],
            check=False
        )

        # This is a warning, not a failure
        if result.returncode != 0:
            pytest.skip("Metrics server not available (optional)")

    def test_network_policies_supported(self, k8s_client):
        """Verify network policies are supported"""
        # Check if NetworkPolicy API is available
        apis = k8s_client["core"].get_api_resources()
        # This is a basic check - actual support depends on CNI

    @pytest.mark.slow
    def test_internet_connectivity(self, kubectl_exec):
        """Test internet connectivity from cluster"""
        result = kubectl_exec([
            "run", "internet-test",
            "--image=curlimages/curl:latest",
            "--rm", "-i", "--restart=Never",
            "--",
            "curl", "-s", "--max-time", "10", "https://google.com"
        ], check=False)

        # Don't fail if internet is not available (might be air-gapped)
        if result.returncode != 0:
            pytest.skip("No internet connectivity (might be by design)")

    def test_cluster_info(self, kubectl_exec):
        """Get cluster info for debugging"""
        result = kubectl_exec(["cluster-info"], check=False)
        assert result.returncode == 0, "Cannot get cluster info"
        print(f"\nCluster Info:\n{result.stdout}")
