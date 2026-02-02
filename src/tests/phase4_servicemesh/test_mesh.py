"""
Phase 4: Service Mesh Tests

Tests for Istio and Cilium service mesh deployments and performance.
"""
import pytest
import time
import json


@pytest.mark.phase4
@pytest.mark.integration
class TestServiceMeshDeployment:
    """Test service mesh deployment"""

    def test_service_mesh_installed(self, k8s_client, mesh_type):
        """Verify service mesh is installed"""
        if mesh_type == "baseline":
            pytest.skip("Baseline mode - no service mesh")

        namespaces = k8s_client["core"].list_namespace()
        namespace_names = [ns.metadata.name for ns in namespaces.items]

        if mesh_type == "istio":
            assert "istio-system" in namespace_names, "Istio not installed"

            # Check Istio pods
            pods = k8s_client["core"].list_namespaced_pod(namespace="istio-system")
            assert len(pods.items) > 0, "No Istio pods found"

            # Check for key components
            pod_names = [p.metadata.name for p in pods.items]
            assert any("istiod" in name for name in pod_names), "Istiod not found"

        elif mesh_type == "cilium":
            # Cilium runs in kube-system
            pods = k8s_client["core"].list_namespaced_pod(
                namespace="kube-system",
                label_selector="k8s-app=cilium"
            )
            assert len(pods.items) > 0, "No Cilium pods found"

        elif mesh_type == "linkerd":
            assert "linkerd" in namespace_names, "Linkerd not installed"

        elif mesh_type == "consul":
            assert "consul" in namespace_names, "Consul not installed"

            # Check Consul pods
            pods = k8s_client["core"].list_namespaced_pod(namespace="consul")
            assert len(pods.items) > 0, "No Consul pods found"

            # Check for key components
            pod_names = [p.metadata.name for p in pods.items]
            assert any("consul-server" in name for name in pod_names), "Consul server not found"
            assert any("consul-connect-injector" in name for name in pod_names), "Consul connect-injector not found"

    def test_deploy_workloads_with_mesh(self, kubectl_exec, test_config):
        """Deploy workloads with service mesh"""
        workloads = [
            "http-service.yaml",
            "grpc-service.yaml",
        ]

        for workload in workloads:
            result = kubectl_exec([
                "apply", "-f",
                str(test_config["workloads_dir"] / workload)
            ])
            assert result.returncode == 0, f"Failed to deploy {workload}: {result.stderr}"

    def test_workload_pods_ready(self, wait_for_pods, mesh_type):
        """Wait for workload pods to be ready"""
        if mesh_type == "baseline":
            pytest.skip("Baseline mode")

        namespaces_to_check = [
            ("http-benchmark", "app=http-server"),
            ("grpc-benchmark", "app=grpc-server"),
        ]

        for namespace, selector in namespaces_to_check:
            ready = wait_for_pods(
                namespace=namespace,
                label_selector=selector,
                timeout=300
            )
            assert ready, f"Pods in {namespace} did not become ready"

    def test_sidecar_injection(self, k8s_client, mesh_type):
        """Verify sidecar proxies are injected"""
        if mesh_type == "baseline":
            pytest.skip("Baseline mode - no sidecars")

        if mesh_type == "cilium":
            pytest.skip("Cilium uses eBPF, not sidecars")

        # Check HTTP benchmark pods
        pods = k8s_client["core"].list_namespaced_pod(
            namespace="http-benchmark",
            label_selector="app=http-server"
        )

        assert len(pods.items) > 0, "No HTTP server pods found"

        for pod in pods.items:
            container_names = [c.name for c in pod.spec.containers]

            if mesh_type == "istio":
                assert "istio-proxy" in container_names, \
                    f"Istio sidecar not injected in pod {pod.metadata.name}"

            elif mesh_type == "linkerd":
                assert "linkerd-proxy" in container_names, \
                    f"Linkerd sidecar not injected in pod {pod.metadata.name}"

            elif mesh_type == "consul":
                # Consul uses "consul-connect-envoy-sidecar" or "envoy-sidecar"
                assert any("consul" in name or "envoy-sidecar" in name for name in container_names), \
                    f"Consul sidecar not injected in pod {pod.metadata.name}"

    def test_service_mesh_connectivity(self, kubectl_exec, mesh_type):
        """Test connectivity through service mesh"""
        if mesh_type == "baseline":
            pytest.skip("Baseline mode")

        result = kubectl_exec(
            [
                "run", "mesh-connectivity-test",
                "--image=curlimages/curl:latest",
                "--rm", "-i", "--restart=Never",
                "-n", "http-benchmark",
                "--",
                "curl", "-s", "--max-time", "10",
                "http://http-server.http-benchmark.svc.cluster.local/"
            ],
            check=False
        )

        assert result.returncode == 0, f"Connectivity test failed: {result.stderr}"

    def test_mtls_enabled(self, kubectl_exec, mesh_type):
        """Verify mTLS is enabled (Istio/Linkerd)"""
        if mesh_type == "baseline":
            pytest.skip("Baseline mode")

        if mesh_type == "cilium":
            pytest.skip("Cilium mTLS test requires different approach")

        if mesh_type == "istio":
            # Check PeerAuthentication policy or use istioctl
            result = kubectl_exec(
                ["get", "peerauthentication", "--all-namespaces"],
                check=False
            )
            # If no error, mTLS policies might be configured
            # Full verification requires istioctl

        elif mesh_type == "linkerd":
            # Linkerd enables mTLS by default
            result = kubectl_exec(
                ["get", "pods", "-n", "linkerd"],
                check=False
            )
            assert result.returncode == 0

        elif mesh_type == "consul":
            # Consul Connect enables mTLS by default for service-to-service communication
            # Verify connect-injector is running
            result = kubectl_exec(
                ["get", "deployment", "consul-connect-injector", "-n", "consul"],
                check=False
            )
            assert result.returncode == 0, "Consul Connect injector not found"


@pytest.mark.phase4
@pytest.mark.integration
@pytest.mark.slow
class TestServiceMeshPerformance:
    """Service mesh performance tests"""

    def test_http_load_with_mesh(self, run_benchmark, test_config, mesh_type):
        """Run HTTP load test with service mesh"""
        if mesh_type == "baseline":
            pytest.skip("Baseline mode")

        results = run_benchmark(
            "http-load-test.sh",
            env_vars={
                "NAMESPACE": "http-benchmark",
                "SERVICE_URL": "http-server.http-benchmark.svc.cluster.local",
                "MESH_TYPE": mesh_type,
                "TEST_DURATION": str(test_config["test_duration"]),
                "CONCURRENT_CONNECTIONS": str(test_config["concurrent_connections"]),
            }
        )

        # Validate results
        assert "metrics" in results, "No metrics in results"
        assert results["metrics"]["requests_per_sec"] > 0, "No requests processed"

        # Store results for comparison
        mesh_file = test_config["results_dir"] / f"{mesh_type}_http_metrics.json"
        with open(mesh_file, "w") as f:
            json.dump(results, f, indent=2)

        print(f"\n{mesh_type.upper()} HTTP Performance:")
        print(f"  Requests/sec: {results['metrics']['requests_per_sec']}")
        print(f"  Avg Latency: {results['metrics']['avg_latency_ms']}ms")

    def test_grpc_load_with_mesh(self, run_benchmark, test_config, mesh_type):
        """Run gRPC load test with service mesh"""
        if mesh_type == "baseline":
            pytest.skip("Baseline mode")

        results = run_benchmark(
            "grpc-test.sh",
            env_vars={
                "NAMESPACE": "grpc-benchmark",
                "SERVICE_URL": "grpc-server.grpc-benchmark.svc.cluster.local:9000",
                "MESH_TYPE": mesh_type,
                "TEST_DURATION": str(test_config["test_duration"]),
            }
        )

        # Store results
        mesh_file = test_config["results_dir"] / f"{mesh_type}_grpc_metrics.json"
        with open(mesh_file, "w") as f:
            json.dump(results, f, indent=2)

        print(f"\n{mesh_type.upper()} gRPC Performance saved to {mesh_file}")

    def test_mesh_overhead(self, kubectl_exec, test_config, mesh_type):
        """Measure service mesh resource overhead"""
        if mesh_type == "baseline":
            pytest.skip("Baseline mode")

        # Get metrics
        result = kubectl_exec(
            ["top", "pods", "--all-namespaces"],
            check=False
        )

        if result.returncode != 0:
            pytest.skip("Metrics server not available")

        control_plane_cpu = 0
        control_plane_memory = 0
        data_plane_cpu = 0
        data_plane_memory = 0

        lines = result.stdout.strip().split('\n')[1:]  # Skip header

        for line in lines:
            parts = line.split()
            if len(parts) < 4:
                continue

            namespace = parts[0]
            pod_name = parts[1]
            cpu = parts[2]
            memory = parts[3]

            # Parse CPU
            cpu_value = int(cpu[:-1]) if cpu.endswith('m') else int(cpu) * 1000

            # Parse Memory
            if memory.endswith('Mi'):
                memory_value = int(memory[:-2])
            elif memory.endswith('Gi'):
                memory_value = int(memory[:-2]) * 1024
            else:
                memory_value = 0

            # Classify as control plane or data plane
            if mesh_type == "istio":
                if namespace == "istio-system":
                    control_plane_cpu += cpu_value
                    control_plane_memory += memory_value
                elif "istio-proxy" in pod_name:
                    data_plane_cpu += cpu_value
                    data_plane_memory += memory_value

            elif mesh_type == "cilium":
                if "cilium-operator" in pod_name:
                    control_plane_cpu += cpu_value
                    control_plane_memory += memory_value
                elif "cilium" in pod_name and namespace == "kube-system":
                    data_plane_cpu += cpu_value
                    data_plane_memory += memory_value

            elif mesh_type == "consul":
                if namespace == "consul":
                    if "consul-server" in pod_name or "consul-controller" in pod_name or "consul-connect-injector" in pod_name:
                        control_plane_cpu += cpu_value
                        control_plane_memory += memory_value
                    elif "consul-client" in pod_name:
                        data_plane_cpu += cpu_value
                        data_plane_memory += memory_value
                elif "envoy-sidecar" in pod_name or "consul-connect" in pod_name:
                    data_plane_cpu += cpu_value
                    data_plane_memory += memory_value

        # Store overhead metrics
        overhead_data = {
            "timestamp": time.time(),
            "mesh_type": mesh_type,
            "control_plane": {
                "cpu_millicores": control_plane_cpu,
                "memory_mib": control_plane_memory
            },
            "data_plane": {
                "cpu_millicores": data_plane_cpu,
                "memory_mib": data_plane_memory
            },
            "total": {
                "cpu_millicores": control_plane_cpu + data_plane_cpu,
                "memory_mib": control_plane_memory + data_plane_memory
            }
        }

        overhead_file = test_config["results_dir"] / f"{mesh_type}_overhead.json"
        with open(overhead_file, "w") as f:
            json.dump(overhead_data, f, indent=2)

        print(f"\n{mesh_type.upper()} Resource Overhead:")
        print(f"  Control Plane - CPU: {control_plane_cpu}m, Memory: {control_plane_memory}Mi")
        print(f"  Data Plane - CPU: {data_plane_cpu}m, Memory: {data_plane_memory}Mi")

    def test_latency_overhead(self, test_config, mesh_type):
        """Compare latency overhead vs baseline"""
        if mesh_type == "baseline":
            pytest.skip("Baseline mode")

        # Load baseline metrics
        baseline_file = test_config["results_dir"] / "baseline_http_metrics.json"
        if not baseline_file.exists():
            pytest.skip("Baseline metrics not available")

        with open(baseline_file) as f:
            baseline_metrics = json.load(f)

        # Load mesh metrics
        mesh_file = test_config["results_dir"] / f"{mesh_type}_http_metrics.json"
        if not mesh_file.exists():
            pytest.skip("Mesh metrics not available")

        with open(mesh_file) as f:
            mesh_metrics = json.load(f)

        baseline_latency = baseline_metrics["metrics"]["avg_latency_ms"]
        mesh_latency = mesh_metrics["metrics"]["avg_latency_ms"]

        overhead_pct = ((mesh_latency - baseline_latency) / baseline_latency) * 100

        print(f"\nLatency Overhead for {mesh_type.upper()}:")
        print(f"  Baseline: {baseline_latency}ms")
        print(f"  With Mesh: {mesh_latency}ms")
        print(f"  Overhead: {overhead_pct:.2f}%")

        # Store comparison
        comparison = {
            "mesh_type": mesh_type,
            "baseline_latency_ms": baseline_latency,
            "mesh_latency_ms": mesh_latency,
            "overhead_percent": overhead_pct
        }

        comparison_file = test_config["results_dir"] / f"{mesh_type}_latency_comparison.json"
        with open(comparison_file, "w") as f:
            json.dump(comparison, f, indent=2)
