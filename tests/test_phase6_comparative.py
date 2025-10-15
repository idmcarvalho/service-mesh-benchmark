"""
Phase 6: Comparative Analysis Tests

Tests that compare performance across different service mesh implementations.
"""
import pytest
import json
from pathlib import Path
from tabulate import tabulate


"""Comparative analysis across service meshes"""
@pytest.mark.phase6
class TestComparativeAnalysis:
    
    """Verify all metrics files exist"""
    def test_load_all_metrics(self, test_config):
        results_dir = test_config["results_dir"]

        expected_files = [
            "baseline_http_metrics.json",
            "baseline_resources.json",
        ]

        # Check which mesh types have results
        mesh_types = []
        for mesh_type in ["istio", "cilium", "linkerd"]:
            http_file = results_dir / f"{mesh_type}_http_metrics.json"
            if http_file.exists():
                mesh_types.append(mesh_type)
                expected_files.append(f"{mesh_type}_http_metrics.json")
                expected_files.append(f"{mesh_type}_overhead.json")

        missing_files = []
        for filename in expected_files:
            filepath = results_dir / filename
            if not filepath.exists():
                missing_files.append(filename)

        if missing_files:
            pytest.skip(f"Missing metrics files: {missing_files}")

    """Compare latency across all service meshes"""
    def test_compare_latency(self, test_config):
        results_dir = test_config["results_dir"]

        # Load baseline
        baseline_file = results_dir / "baseline_http_metrics.json"
        if not baseline_file.exists():
            pytest.skip("Baseline metrics not available")

        with open(baseline_file) as f:
            baseline = json.load(f)

        baseline_latency = baseline["metrics"]["avg_latency_ms"]

        # Load mesh metrics
        comparison_data = [
            ["Service Mesh", "Avg Latency (ms)", "vs Baseline", "Overhead %"]
        ]

        comparison_data.append([
            "Baseline",
            f"{baseline_latency:.2f}",
            "-",
            "0%"
        ])

        for mesh_type in ["istio", "cilium", "linkerd"]:
            mesh_file = results_dir / f"{mesh_type}_http_metrics.json"
            if mesh_file.exists():
                with open(mesh_file) as f:
                    mesh_metrics = json.load(f)

                mesh_latency = mesh_metrics["metrics"]["avg_latency_ms"]
                overhead_pct = ((mesh_latency - baseline_latency) / baseline_latency) * 100

                comparison_data.append([
                    mesh_type.capitalize(),
                    f"{mesh_latency:.2f}",
                    f"+{mesh_latency - baseline_latency:.2f}ms",
                    f"+{overhead_pct:.1f}%"
                ])

        # Print comparison table
        print("\n" + "="*60)
        print("LATENCY COMPARISON")
        print("="*60)
        print(tabulate(comparison_data, headers="firstrow", tablefmt="grid"))

        # Save to file
        comparison_file = results_dir / "latency_comparison.json"
        with open(comparison_file, "w") as f:
            json.dump({
                "baseline_latency_ms": baseline_latency,
                "comparisons": comparison_data[1:]
            }, f, indent=2)

    """Compare throughput across all service meshes"""
    def test_compare_throughput(self, test_config):
        results_dir = test_config["results_dir"]

        # Load baseline
        baseline_file = results_dir / "baseline_http_metrics.json"
        if not baseline_file.exists():
            pytest.skip("Baseline metrics not available")

        with open(baseline_file) as f:
            baseline = json.load(f)

        baseline_throughput = baseline["metrics"]["requests_per_sec"]

        # Load mesh metrics
        comparison_data = [
            ["Service Mesh", "Requests/sec", "vs Baseline", "Change %"]
        ]

        comparison_data.append([
            "Baseline",
            f"{baseline_throughput:.2f}",
            "-",
            "0%"
        ])

        for mesh_type in ["istio", "cilium", "linkerd"]:
            mesh_file = results_dir / f"{mesh_type}_http_metrics.json"
            if mesh_file.exists():
                with open(mesh_file) as f:
                    mesh_metrics = json.load(f)

                mesh_throughput = mesh_metrics["metrics"]["requests_per_sec"]
                change_pct = ((mesh_throughput - baseline_throughput) / baseline_throughput) * 100

                comparison_data.append([
                    mesh_type.capitalize(),
                    f"{mesh_throughput:.2f}",
                    f"{mesh_throughput - baseline_throughput:+.2f}",
                    f"{change_pct:+.1f}%"
                ])

        # Print comparison table
        print("\n" + "="*60)
        print("THROUGHPUT COMPARISON")
        print("="*60)
        print(tabulate(comparison_data, headers="firstrow", tablefmt="grid"))

    """Compare resource overhead across service meshes"""
    def test_compare_resource_overhead(self, test_config):
        results_dir = test_config["results_dir"]

        # Load baseline
        baseline_file = results_dir / "baseline_resources.json"
        if not baseline_file.exists():
            pytest.skip("Baseline resource metrics not available")

        with open(baseline_file) as f:
            baseline = json.load(f)

        baseline_cpu = baseline.get("total_cpu_millicores", 0)
        baseline_memory = baseline.get("total_memory_mib", 0)

        # Compare overhead
        comparison_data = [
            ["Service Mesh", "CPU (m)", "Memory (Mi)", "CPU Overhead", "Mem Overhead"]
        ]

        comparison_data.append([
            "Baseline",
            str(baseline_cpu),
            str(baseline_memory),
            "-",
            "-"
        ])

        for mesh_type in ["istio", "cilium", "linkerd"]:
            overhead_file = results_dir / f"{mesh_type}_overhead.json"
            if overhead_file.exists():
                with open(overhead_file) as f:
                    overhead = json.load(f)

                total_cpu = overhead["total"]["cpu_millicores"]
                total_memory = overhead["total"]["memory_mib"]

                cpu_overhead_pct = ((total_cpu - baseline_cpu) / baseline_cpu * 100) if baseline_cpu > 0 else 0
                mem_overhead_pct = ((total_memory - baseline_memory) / baseline_memory * 100) if baseline_memory > 0 else 0

                comparison_data.append([
                    mesh_type.capitalize(),
                    str(total_cpu),
                    str(total_memory),
                    f"+{cpu_overhead_pct:.1f}%",
                    f"+{mem_overhead_pct:.1f}%"
                ])

        # Print comparison table
        print("\n" + "="*60)
        print("RESOURCE OVERHEAD COMPARISON")
        print("="*60)
        print(tabulate(comparison_data, headers="firstrow", tablefmt="grid"))

    """Generate comprehensive summary report"""
    def test_generate_summary_report(self, test_config):
        results_dir = test_config["results_dir"]

        summary = {
            "test_date": str(Path(results_dir).stat().st_mtime),
            "meshes_tested": [],
            "key_findings": {}
        }

        # Detect which meshes were tested
        for mesh_type in ["baseline", "istio", "cilium", "linkerd"]:
            http_file = results_dir / f"{mesh_type}_http_metrics.json"
            if http_file.exists():
                summary["meshes_tested"].append(mesh_type)

        # Load key metrics
        for mesh_type in summary["meshes_tested"]:
            http_file = results_dir / f"{mesh_type}_http_metrics.json"

            with open(http_file) as f:
                metrics = json.load(f)

            summary["key_findings"][mesh_type] = {
                "avg_latency_ms": metrics["metrics"]["avg_latency_ms"],
                "requests_per_sec": metrics["metrics"]["requests_per_sec"],
            }

            # Add overhead if not baseline
            if mesh_type != "baseline":
                overhead_file = results_dir / f"{mesh_type}_overhead.json"
                if overhead_file.exists():
                    with open(overhead_file) as f:
                        overhead = json.load(f)

                    summary["key_findings"][mesh_type]["overhead"] = {
                        "cpu_millicores": overhead["total"]["cpu_millicores"],
                        "memory_mib": overhead["total"]["memory_mib"]
                    }

        # Save summary
        summary_file = results_dir / "test_summary.json"
        with open(summary_file, "w") as f:
            json.dump(summary, f, indent=2)

        print("\n" + "="*60)
        print("TEST SUMMARY")
        print("="*60)
        print(f"Meshes Tested: {', '.join(summary['meshes_tested'])}")
        print(f"Summary saved to: {summary_file}")

    """Determine best performing service mesh"""
    def test_determine_best_performer(self, test_config):
    
        results_dir = test_config["results_dir"]

        meshes = []
        for mesh_type in ["istio", "cilium", "linkerd"]:
            http_file = results_dir / f"{mesh_type}_http_metrics.json"
            overhead_file = results_dir / f"{mesh_type}_overhead.json"

            if http_file.exists() and overhead_file.exists():
                with open(http_file) as f:
                    metrics = json.load(f)
                with open(overhead_file) as f:
                    overhead = json.load(f)

                meshes.append({
                    "name": mesh_type,
                    "latency": metrics["metrics"]["avg_latency_ms"],
                    "throughput": metrics["metrics"]["requests_per_sec"],
                    "cpu_overhead": overhead["total"]["cpu_millicores"],
                    "memory_overhead": overhead["total"]["memory_mib"]
                })

        if not meshes:
            pytest.skip("No service mesh metrics available for comparison")

        # Determine winners
        lowest_latency = min(meshes, key=lambda x: x["latency"])
        highest_throughput = max(meshes, key=lambda x: x["throughput"])
        lowest_cpu = min(meshes, key=lambda x: x["cpu_overhead"])
        lowest_memory = min(meshes, key=lambda x: x["memory_overhead"])

        print("\n" + "="*60)
        print("BEST PERFORMERS")
        print("="*60)
        print(f"Lowest Latency: {lowest_latency['name'].upper()} ({lowest_latency['latency']:.2f}ms)")
        print(f"Highest Throughput: {highest_throughput['name'].upper()} ({highest_throughput['throughput']:.2f} req/s)")
        print(f"Lowest CPU Overhead: {lowest_cpu['name'].upper()} ({lowest_cpu['cpu_overhead']}m)")
        print(f"Lowest Memory Overhead: {lowest_memory['name'].upper()} ({lowest_memory['memory_overhead']}Mi)")

        # Save winners
        winners = {
            "lowest_latency": lowest_latency["name"],
            "highest_throughput": highest_throughput["name"],
            "lowest_cpu_overhead": lowest_cpu["name"],
            "lowest_memory_overhead": lowest_memory["name"]
        }

        winners_file = results_dir / "best_performers.json"
        with open(winners_file, "w") as f:
            json.dump(winners, f, indent=2)
