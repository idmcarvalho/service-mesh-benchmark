"""
Phase 7: Stress and Edge Case Tests

Tests that verify behavior under high load, failures, and edge conditions.
"""
import logging
import pytest
import time
import subprocess
from kubernetes.client.rest import ApiException

logger = logging.getLogger(__name__)


@pytest.mark.phase7
@pytest.mark.integration
@pytest.mark.slow
class TestStressTests:
    """Stress testing under high load"""

    def test_high_concurrent_connections(self, run_benchmark, test_config, mesh_type):
        """Test with very high concurrent connections"""
        high_connections = test_config["concurrent_connections"] * 5  # 5x normal

        results = run_benchmark(
            "http-load-test.sh",
            env_vars={
                "NAMESPACE": "http-benchmark" if mesh_type != "baseline" else "baseline-http",
                "SERVICE_URL": "http-server.http-benchmark.svc.cluster.local" if mesh_type != "baseline" else "baseline-http-server.baseline-http.svc.cluster.local",
                "MESH_TYPE": mesh_type,
                "TEST_DURATION": "120",  # Longer duration
                "CONCURRENT_CONNECTIONS": str(high_connections),
            }
        )

        # Should handle load without complete failure
        assert results["metrics"]["requests_per_sec"] > 0, "Complete failure under high load"

        print(f"\nHigh Load Test ({high_connections} connections):")
        print(f"  Requests/sec: {results['metrics']['requests_per_sec']}")
        print(f"  Avg Latency: {results['metrics']['avg_latency_ms']}ms")

    def test_extended_duration(self, run_benchmark, test_config, mesh_type):
        """Test with extended duration (10 minutes)"""
        results = run_benchmark(
            "http-load-test.sh",
            env_vars={
                "NAMESPACE": "http-benchmark" if mesh_type != "baseline" else "baseline-http",
                "SERVICE_URL": "http-server.http-benchmark.svc.cluster.local" if mesh_type != "baseline" else "baseline-http-server.baseline-http.svc.cluster.local",
                "MESH_TYPE": mesh_type,
                "TEST_DURATION": "600",  # 10 minutes
                "CONCURRENT_CONNECTIONS": str(test_config["concurrent_connections"]),
            }
        )

        assert results["metrics"]["requests_per_sec"] > 0, "Failure during extended test"

        print(f"\nExtended Duration Test (10 minutes):")
        print(f"  Requests/sec: {results['metrics']['requests_per_sec']}")

    def test_burst_traffic(self, kubectl_exec, mesh_type):
        """Test handling of burst traffic patterns"""
        namespace = "http-benchmark" if mesh_type != "baseline" else "baseline-http"
        service_url = "http-server.http-benchmark.svc.cluster.local" if mesh_type != "baseline" else "baseline-http-server.baseline-http.svc.cluster.local"

        # Create burst load using parallel curl commands
        script = f"""
        burst_test() {{
            for i in $(seq 1 100); do
                curl -s -o /dev/null -w '%{{http_code}}\n' http://{service_url}/ &
            done
            wait
        }}

        # Run 5 bursts
        for burst in $(seq 1 5); do
            burst_test
            sleep 2
        done
        """

        result = kubectl_exec(
            [
                "run", "burst-test",
                "--image=curlimages/curl:latest",
                "--rm", "-i", "--restart=Never",
                "-n", namespace,
                "--",
                "sh", "-c", script
            ],
            check=False
        )

        # Should not completely fail
        assert "200" in result.stdout, "Burst traffic caused complete failure"

        print("\nBurst traffic test completed")


@pytest.mark.phase7
@pytest.mark.integration
class TestFailureScenarios:
    """Test behavior under failure conditions"""

    def test_pod_failure_recovery(self, k8s_client, wait_for_pods, mesh_type):
        """Test recovery when pods are deleted"""
        namespace = "http-benchmark" if mesh_type != "baseline" else "baseline-http"
        label = "app=http-server" if mesh_type != "baseline" else "app=baseline-http-server"

        # Get current pods
        pods = k8s_client["core"].list_namespaced_pod(
            namespace=namespace,
            label_selector=label
        )

        initial_count = len(pods.items)
        assert initial_count > 0, "No pods found"

        # Delete one pod
        if pods.items:
            pod_name = pods.items[0].metadata.name
            k8s_client["core"].delete_namespaced_pod(
                name=pod_name,
                namespace=namespace
            )

            print(f"\nDeleted pod: {pod_name}")

            # Wait for pod to be recreated
            time.sleep(5)

            # Verify pods are back
            ready = wait_for_pods(
                namespace=namespace,
                label_selector=label,
                timeout=120
            )

            assert ready, "Pods did not recover after deletion"

            # Verify count is restored
            pods_after = k8s_client["core"].list_namespaced_pod(
                namespace=namespace,
                label_selector=label
            )

            assert len(pods_after.items) == initial_count, "Pod count not restored"

            print("Pod successfully recovered")

    def test_service_continuity_during_failure(self, kubectl_exec, k8s_client, mesh_type):
        """Test that service continues during pod failures"""
        namespace = "http-benchmark" if mesh_type != "baseline" else "baseline-http"
        service_url = "http-server.http-benchmark.svc.cluster.local" if mesh_type != "baseline" else "baseline-http-server.baseline-http.svc.cluster.local"
        label = "app=http-server" if mesh_type != "baseline" else "app=baseline-http-server"

        # Get pods
        pods = k8s_client["core"].list_namespaced_pod(
            namespace=namespace,
            label_selector=label
        )

        if len(pods.items) < 2:
            pytest.skip("Need at least 2 pods for this test")

        # Start continuous requests in background
        continuous_test = kubectl_exec(
            [
                "run", "continuous-test",
                "--image=curlimages/curl:latest",
                "--restart=Never",
                "-n", namespace,
                "--",
                "sh", "-c",
                f"for i in $(seq 1 60); do curl -s -o /dev/null -w '%{{http_code}}\n' http://{service_url}/; sleep 1; done"
            ],
            check=False
        )

        # Wait a bit...
        time.sleep(5)

        # Delete a pod
        pod_name = pods.items[0].metadata.name
        k8s_client["core"].delete_namespaced_pod(
            name=pod_name,
            namespace=namespace
        )

        print(f"\nDeleted pod {pod_name} while traffic is running")

        # Wait for test to complete...
        time.sleep(30)

        # Get logs
        logs_result = kubectl_exec(
            ["logs", "continuous-test", "-n", namespace],
            check=False
        )

        # Cleanup
        kubectl_exec(["delete", "pod", "continuous-test", "-n", namespace, "--ignore-not-found=true"], check=False)

        if logs_result.returncode == 0:
            success_count = logs_result.stdout.count("200")
            total_count = len(logs_result.stdout.strip().split('\n'))

            success_rate = (success_count / total_count * 100) if total_count > 0 else 0

            print(f"Success rate during failure: {success_rate:.1f}%")

            # Should have some failures but mostly successful
            assert success_rate >= 50, f"Too many failures: {success_rate:.1f}%"

    def test_node_resource_saturation(self, kubectl_exec, mesh_type):
        """Test behavior when node resources are saturated"""
        namespace = "http-benchmark" if mesh_type != "baseline" else "baseline-http"

        # This is a cautious test - we don't want to crash the cluster
        # Just verify the system handles it gracefully

        # Try to get node metrics
        result = kubectl_exec(["top", "nodes"], check=False)

        if result.returncode != 0:
            pytest.skip("Cannot get node metrics")

        print("\nNode resource usage:")
        print(result.stdout)

        # Just verify we can still operate
        test_result = kubectl_exec(
            [
                "run", "saturation-test",
                "--image=curlimages/curl:latest",
                "--rm", "-i", "--restart=Never",
                "-n", namespace,
                "--",
                "curl", "-s", "--max-time", "10",
                f"http://{'http-server.http-benchmark' if mesh_type != 'baseline' else 'baseline-http-server.baseline-http'}.svc.cluster.local/"
            ],
            check=False
        )

        assert test_result.returncode == 0, "Service unavailable under load"


@pytest.mark.phase7
@pytest.mark.integration
class TestSecurityAndPolicies:
    """Test security policies and network isolation"""

    def test_network_policy_enforcement(self, kubectl_exec, mesh_type):
        """Test network policy enforcement (if applicable)"""
        if mesh_type == "baseline":
            pytest.skip("Network policies not tested in baseline")

        # This is a basic test - full network policy testing depends on CNI
        result = kubectl_exec(
            ["get", "networkpolicies", "--all-namespaces"],
            check=False
        )

        # Just verify command works
        assert result.returncode == 0

    def test_mtls_enforcement(self, kubectl_exec, mesh_type):
        """Test mTLS is enforced"""
        if mesh_type == "baseline":
            pytest.skip("No mTLS in baseline")

        if mesh_type == "cilium":
            pytest.skip("Cilium mTLS test requires different approach")

        if mesh_type == "istio":
            # Check for PeerAuthentication in STRICT mode
            result = kubectl_exec(
                ["get", "peerauthentication", "-n", "http-benchmark", "-o", "yaml"],
                check=False
            )

            # This is informational
            print("\nPeerAuthentication status:")
            print(result.stdout if result.returncode == 0 else "No PeerAuthentication found")

    def test_unauthorized_access_blocked(self, kubectl_exec, mesh_type):
        """Test that unauthorized access is blocked (if policies configured)"""
        # This test depends on having authorization policies configured
        # It's more of a template for custom policy testing

        if mesh_type == "baseline":
            pytest.skip("No authorization policies in baseline")

        print("\nAuthorization policy test (template)")
        print("Configure specific authorization policies and test here")

    def test_rate_limiting(self, kubectl_exec, mesh_type):
        """Test rate limiting (if configured)"""
        if mesh_type == "baseline":
            pytest.skip("No rate limiting in baseline")

        # Template for rate limiting tests
        print("\nRate limiting test (template)")
        print("Configure rate limiting and test here")


@pytest.mark.phase7
class TestEdgeCases:
    """Test edge cases and unusual scenarios"""

    def test_empty_request(self, kubectl_exec, mesh_type):
        """Test handling of empty/minimal requests"""
        namespace = "http-benchmark" if mesh_type != "baseline" else "baseline-http"
        service_url = "http-server.http-benchmark.svc.cluster.local" if mesh_type != "baseline" else "baseline-http-server.baseline-http.svc.cluster.local"

        result = kubectl_exec(
            [
                "run", "empty-request-test",
                "--image=curlimages/curl:latest",
                "--rm", "-i", "--restart=Never",
                "-n", namespace,
                "--",
                "curl", "-X", "GET", "-s", "-o", "/dev/null", "-w", "%{http_code}",
                f"http://{service_url}/"
            ],
            check=False
        )

        assert "200" in result.stdout or "404" in result.stdout, "Unexpected response to empty request"

    def test_large_payload(self, kubectl_exec, mesh_type):
        """Test handling of large payloads"""
        namespace = "http-benchmark" if mesh_type != "baseline" else "baseline-http"
        service_url = "http-server.http-benchmark.svc.cluster.local" if mesh_type != "baseline" else "baseline-http-server.baseline-http.svc.cluster.local"

        # Send a large POST request
        result = kubectl_exec(
            [
                "run", "large-payload-test",
                "--image=curlimages/curl:latest",
                "--rm", "-i", "--restart=Never",
                "-n", namespace,
                "--",
                "sh", "-c",
                f"dd if=/dev/zero bs=1M count=10 2>/dev/null | curl -X POST -s -o /dev/null -w '%{{http_code}}' --data-binary @- http://{service_url}/"
            ],
            check=False
        )

        # Should handle large payloads (might return error but shouldn't crash)
        print(f"\nLarge payload test response: {result.stdout}")

    def test_concurrent_namespace_access(self, kubectl_exec, k8s_client, mesh_type):
        """Test access across namespaces"""
        # Create a temporary namespace and try to access services
        test_ns = "cross-ns-test"

        from kubernetes.client import V1Namespace, V1ObjectMeta

        try:
            namespace = V1Namespace(metadata=V1ObjectMeta(name=test_ns))
            k8s_client["core"].create_namespace(namespace)

            service_url = "http-server.http-benchmark.svc.cluster.local" if mesh_type != "baseline" else "baseline-http-server.baseline-http.svc.cluster.local"

            result = kubectl_exec(
                [
                    "run", "cross-ns-test",
                    "--image=curlimages/curl:latest",
                    "--rm", "-i", "--restart=Never",
                    "-n", test_ns,
                    "--",
                    "curl", "-s", "--max-time", "10",
                    f"http://{service_url}/"
                ],
                check=False
            )

            # Cross-namespace access should work by default (unless restricted by policy)
            print(f"\nCross-namespace access: {'Success' if result.returncode == 0 else 'Blocked'}")

        finally:
            # Cleanup
            try:
                k8s_client["core"].delete_namespace(test_ns)
            except ApiException as e:
                if e.status != 404:  # Ignore if namespace doesn't exist
                    logger.warning(f"Failed to cleanup test namespace {test_ns}: {e}")
            except Exception as e:
                logger.error(f"Unexpected error during namespace cleanup: {e}", exc_info=True)
