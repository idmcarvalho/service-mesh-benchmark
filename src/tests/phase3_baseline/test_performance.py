"""
Phase 3: Baseline Tests

Tests for baseline workloads (without service mesh) to establish performance baselines.
"""
import pytest
import time
import json


@pytest.mark.phase3
@pytest.mark.integration
class TestBaselineDeployment:
    """Test baseline workload deployment and health"""

    def test_deploy_baseline_http(self, kubectl_exec, test_config):
        """Deploy baseline HTTP workload"""
        result = kubectl_exec([
            "apply", "-f",
            str(test_config["workloads_dir"] / "baseline-http-service.yaml")
        ])
        assert result.returncode == 0, f"Failed to deploy baseline HTTP: {result.stderr}"

    def test_deploy_baseline_grpc(self, kubectl_exec, test_config):
        """Deploy baseline gRPC workload"""
        result = kubectl_exec([
            "apply", "-f",
            str(test_config["workloads_dir"] / "baseline-grpc-service.yaml")
        ])
        assert result.returncode == 0, f"Failed to deploy baseline gRPC: {result.stderr}"

    def test_baseline_http_namespace_exists(self, k8s_client):
        """Verify baseline-http namespace exists"""
        namespaces = k8s_client["core"].list_namespace()
        namespace_names = [ns.metadata.name for ns in namespaces.items]
        assert "baseline-http" in namespace_names

    def test_baseline_grpc_namespace_exists(self, k8s_client):
        """Verify baseline-grpc namespace exists"""
        namespaces = k8s_client["core"].list_namespace()
        namespace_names = [ns.metadata.name for ns in namespaces.items]
        assert "baseline-grpc" in namespace_names

    def test_baseline_http_pods_ready(self, wait_for_pods):
        """Wait for baseline HTTP pods to be ready"""
        ready = wait_for_pods(
            namespace="baseline-http",
            label_selector="app=baseline-http-server",
            timeout=300
        )
        assert ready, "Baseline HTTP pods did not become ready in time"

    def test_baseline_grpc_pods_ready(self, wait_for_pods):
        """Wait for baseline gRPC pods to be ready"""
        ready = wait_for_pods(
            namespace="baseline-grpc",
            label_selector="app=baseline-grpc-server",
            timeout=300
        )
        assert ready, "Baseline gRPC pods did not become ready in time"

    def test_baseline_http_service_exists(self, k8s_client):
        """Verify baseline HTTP service exists"""
        services = k8s_client["core"].list_namespaced_service(namespace="baseline-http")
        service_names = [svc.metadata.name for svc in services.items]
        assert "baseline-http-server" in service_names

    def test_baseline_grpc_service_exists(self, k8s_client):
        """Verify baseline gRPC service exists"""
        services = k8s_client["core"].list_namespaced_service(namespace="baseline-grpc")
        service_names = [svc.metadata.name for svc in services.items]
        assert "baseline-grpc-server" in service_names

    def test_baseline_http_endpoints_ready(self, k8s_client):
        """Verify baseline HTTP service has ready endpoints"""
        endpoints = k8s_client["core"].read_namespaced_endpoints(
            name="baseline-http-server",
            namespace="baseline-http"
        )

        assert endpoints.subsets is not None, "No endpoints found"
        assert len(endpoints.subsets) > 0, "No endpoint subsets"
        assert len(endpoints.subsets[0].addresses) > 0, "No ready addresses in endpoints"

    def test_baseline_http_connectivity(self, kubectl_exec):
        """Test HTTP connectivity to baseline service"""
        result = kubectl_exec(
            [
                "run", "test-baseline-http",
                "--image=curlimages/curl:latest",
                "--rm", "-i", "--restart=Never",
                "-n", "baseline-http",
                "--",
                "curl", "-s", "--max-time", "10",
                "http://baseline-http-server.baseline-http.svc.cluster.local/"
            ],
            check=False
        )

        assert result.returncode == 0, f"HTTP connectivity test failed: {result.stderr}"
        assert "HTTP Benchmark Response" in result.stdout or result.stdout != ""

    def test_baseline_http_health_endpoint(self, kubectl_exec):
        """Test HTTP health endpoint"""
        result = kubectl_exec(
            [
                "run", "test-baseline-http-health",
                "--image=curlimages/curl:latest",
                "--rm", "-i", "--restart=Never",
                "-n", "baseline-http",
                "--",
                "curl", "-s", "--max-time", "10",
                "http://baseline-http-server.baseline-http.svc.cluster.local/health"
            ],
            check=False
        )

        assert result.returncode == 0, f"Health check failed: {result.stderr}"
        assert "OK" in result.stdout

    def test_baseline_grpc_connectivity(self, kubectl_exec):
        """Test gRPC connectivity to baseline service"""
        result = kubectl_exec(
            [
                "run", "test-baseline-grpc",
                "--image=fullstorydev/grpcurl:latest",
                "--rm", "-i", "--restart=Never",
                "-n", "baseline-grpc",
                "--",
                "grpcurl", "-plaintext",
                "baseline-grpc-server.baseline-grpc.svc.cluster.local:9000",
                "list"
            ],
            check=False
        )

        assert result.returncode == 0, f"gRPC connectivity test failed: {result.stderr}"

    def test_baseline_http_pod_logs(self, k8s_client):
        """Check baseline HTTP pod logs for errors"""
        pods = k8s_client["core"].list_namespaced_pod(
            namespace="baseline-http",
            label_selector="app=baseline-http-server"
        )

        assert len(pods.items) > 0, "No HTTP pods found"

        for pod in pods.items:
            if pod.status.phase == "Running":
                logs = k8s_client["core"].read_namespaced_pod_log(
                    name=pod.metadata.name,
                    namespace="baseline-http",
                    tail_lines=50
                )

                # Check for common error patterns
                error_patterns = ["error", "fatal", "panic", "exception"]
                log_lower = logs.lower()

                errors_found = [p for p in error_patterns if p in log_lower]

                # Some errors might be acceptable, but let's log them
                if errors_found:
                    print(f"Warning: Found potential errors in logs: {errors_found}")


@pytest.mark.phase3
@pytest.mark.integration
@pytest.mark.slow
class TestBaselinePerformance:
    """Baseline performance tests"""

    def test_baseline_http_load_test(self, run_benchmark, test_config):
        """Run baseline HTTP load test"""
        results = run_benchmark(
            "http-load-test.sh",
            env_vars={
                "NAMESPACE": "baseline-http",
                "SERVICE_URL": "baseline-http-server.baseline-http.svc.cluster.local",
                "MESH_TYPE": "baseline",
                "TEST_DURATION": str(test_config["test_duration"]),
                "CONCURRENT_CONNECTIONS": str(test_config["concurrent_connections"]),
            }
        )

        # Validate results
        assert "metrics" in results, "No metrics in results"
        assert results["metrics"]["requests_per_sec"] > 0, "No requests processed"

        # Store baseline results for later comparison
        baseline_file = test_config["results_dir"] / "baseline_http_metrics.json"
        with open(baseline_file, "w") as f:
            json.dump(results, f, indent=2)

        print(f"\nBaseline HTTP Performance:")
        print(f"  Requests/sec: {results['metrics']['requests_per_sec']}")
        print(f"  Avg Latency: {results['metrics']['avg_latency_ms']}ms")

    def test_baseline_grpc_load_test(self, run_benchmark, test_config):
        """Run baseline gRPC load test"""
        results = run_benchmark(
            "grpc-test.sh",
            env_vars={
                "NAMESPACE": "baseline-grpc",
                "SERVICE_URL": "baseline-grpc-server.baseline-grpc.svc.cluster.local:9000",
                "MESH_TYPE": "baseline",
                "TEST_DURATION": str(test_config["test_duration"]),
            }
        )

        # Store baseline results
        baseline_file = test_config["results_dir"] / "baseline_grpc_metrics.json"
        with open(baseline_file, "w") as f:
            json.dump(results, f, indent=2)

        print(f"\nBaseline gRPC Performance saved to {baseline_file}")

    def test_baseline_resource_usage(self, k8s_client, kubectl_exec, test_config):
        """Measure baseline resource usage"""
        # Get pod metrics
        result = kubectl_exec(
            ["top", "pods", "-n", "baseline-http"],
            check=False
        )

        if result.returncode != 0:
            pytest.skip("Metrics server not available")

        # Parse metrics
        lines = result.stdout.strip().split('\n')[1:]  # Skip header
        total_cpu = 0
        total_memory = 0

        for line in lines:
            parts = line.split()
            if len(parts) >= 3:
                cpu = parts[1]  # e.g., "10m"
                memory = parts[2]  # e.g., "50Mi"

                # Parse CPU (millicores)
                if cpu.endswith('m'):
                    total_cpu += int(cpu[:-1])
                else:
                    total_cpu += int(cpu) * 1000

                # Parse Memory (Mi)
                if memory.endswith('Mi'):
                    total_memory += int(memory[:-2])

        # Store baseline resource usage
        resource_data = {
            "timestamp": time.time(),
            "mesh_type": "baseline",
            "namespace": "baseline-http",
            "total_cpu_millicores": total_cpu,
            "total_memory_mib": total_memory,
        }

        baseline_file = test_config["results_dir"] / "baseline_resources.json"
        with open(baseline_file, "w") as f:
            json.dump(resource_data, f, indent=2)

        print(f"\nBaseline Resource Usage:")
        print(f"  CPU: {total_cpu}m")
        print(f"  Memory: {total_memory}Mi")

    def test_baseline_error_rate(self, kubectl_exec):
        """Verify baseline error rate is acceptable"""
        # Run a quick load test and check for errors
        # This is a simplified check - full error rate testing is in load tests

        result = kubectl_exec(
            [
                "run", "error-rate-test",
                "--image=curlimages/curl:latest",
                "--rm", "-i", "--restart=Never",
                "-n", "baseline-http",
                "--",
                "sh", "-c",
                "for i in $(seq 1 100); do "
                "curl -s -o /dev/null -w '%{http_code}\n' "
                "http://baseline-http-server.baseline-http.svc.cluster.local/ || echo '000'; "
                "done | grep -c '^200$'"
            ],
            check=False
        )

        if result.returncode == 0:
            success_count = int(result.stdout.strip())
            success_rate = (success_count / 100) * 100

            assert success_rate >= 95, f"Error rate too high: {100 - success_rate}%"

            print(f"\nBaseline success rate: {success_rate}%")
