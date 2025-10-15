#!/usr/bin/env python3
"""
Test Orchestration Script

Runs the comprehensive test suite for service mesh benchmarking.
Supports running tests in phases with proper sequencing.
"""
import argparse
import subprocess
import sys
import os
from pathlib import Path
import json
import time


"""Run a command and return the result"""
def run_command(cmd, cwd=None, env=None):
    print(f"\n{'='*60}")
    print(f"Running: {' '.join(cmd)}")
    print(f"{'='*60}")

    result = subprocess.run(
        cmd,
        cwd=cwd,
        env=env or os.environ.copy(),
        capture_output=False,
        text=True
    )

    return result.returncode == 0


"""Run pytest with specified markers"""
def run_pytest(markers=None, extra_args=None, mesh_type="baseline", kubeconfig=None):
    cmd = ["pytest", "-v", "--tb=short"]

    if markers:
        cmd.extend(["-m", markers])

    cmd.extend([
        f"--mesh-type={mesh_type}",
    ])

    if kubeconfig:
        cmd.extend([f"--kubeconfig={kubeconfig}"])

    if extra_args:
        cmd.extend(extra_args)

    # Add HTML report
    cmd.extend([
        "--html=../benchmarks/results/test_report.html",
        "--self-contained-html"
    ])

    # Add JSON report
    cmd.extend([
        "--json-report",
        "--json-report-file=../benchmarks/results/test_report.json"
    ])

    tests_dir = Path(__file__).parent
    return run_command(cmd, cwd=tests_dir)


def main():
    parser = argparse.ArgumentParser(
        description="Service Mesh Benchmark Test Orchestration"
    )

    parser.add_argument(
        "--phase",
        choices=["all", "1", "2", "3", "4", "6", "7", "pre", "infra", "baseline", "mesh", "stress", "compare"],
        default="all",
        help="Test phase to run"
    )

    parser.add_argument(
        "--mesh-type",
        choices=["baseline", "istio", "cilium", "linkerd"],
        default="baseline",
        help="Service mesh type to test"
    )

    parser.add_argument(
        "--kubeconfig",
        default=os.getenv("KUBECONFIG", "~/.kube/config"),
        help="Path to kubeconfig file"
    )

    parser.add_argument(
        "--skip-infra",
        action="store_true",
        help="Skip infrastructure tests"
    )

    parser.add_argument(
        "--test-duration",
        type=int,
        default=60,
        help="Test duration in seconds"
    )

    parser.add_argument(
        "--concurrent-connections",
        type=int,
        default=100,
        help="Concurrent connections for load tests"
    )

    parser.add_argument(
        "--include-slow",
        action="store_true",
        help="Include slow tests"
    )

    parser.add_argument(
        "--parallel",
        type=int,
        default=1,
        help="Number of parallel test workers"
    )

    args = parser.parse_args()

    # Extra pytest args
    extra_args = [
        f"--test-duration={args.test_duration}",
        f"--concurrent-connections={args.concurrent_connections}",
    ]

    if args.skip_infra:
        extra_args.append("--skip-infra")

    if args.parallel > 1:
        extra_args.extend(["-n", str(args.parallel)])

    if not args.include_slow:
        extra_args.extend(["-m", "not slow"])

    # Track results
    results = {}
    start_time = time.time()

    print("\n" + "="*60)
    print("SERVICE MESH BENCHMARK TEST SUITE")
    print("="*60)
    print(f"Phase: {args.phase}")
    print(f"Mesh Type: {args.mesh_type}")
    print(f"Kubeconfig: {args.kubeconfig}")
    print(f"Test Duration: {args.test_duration}s")
    print(f"Concurrent Connections: {args.concurrent_connections}")
    print("="*60 + "\n")

    # Run tests based on phase
    if args.phase in ["all", "1", "pre"]:
        print("\n>>> PHASE 1: Pre-deployment Tests")
        success = run_pytest(
            markers="phase1",
            extra_args=extra_args,
            mesh_type=args.mesh_type,
            kubeconfig=args.kubeconfig
        )
        results["phase1"] = "PASS" if success else "FAIL"

        if not success and args.phase == "all":
            print("\n❌ Phase 1 failed. Fix issues before proceeding.")
            sys.exit(1)

    if args.phase in ["all", "2", "infra"]:
        print("\n>>> PHASE 2: Infrastructure Tests")
        success = run_pytest(
            markers="phase2",
            extra_args=extra_args,
            mesh_type=args.mesh_type,
            kubeconfig=args.kubeconfig
        )
        results["phase2"] = "PASS" if success else "FAIL"

        if not success and args.phase == "all":
            print("\n❌ Phase 2 failed. Infrastructure not ready.")
            sys.exit(1)

    if args.phase in ["all", "3", "baseline"]:
        print("\n>>> PHASE 3: Baseline Tests")
        success = run_pytest(
            markers="phase3",
            extra_args=extra_args,
            mesh_type="baseline",
            kubeconfig=args.kubeconfig
        )
        results["phase3"] = "PASS" if success else "FAIL"

        if not success and args.phase == "all":
            print("\n⚠️  Phase 3 failed. Baseline tests did not complete successfully.")
            # Continue anyway for service mesh tests

    if args.phase in ["all", "4", "mesh"]:
        if args.mesh_type != "baseline":
            print(f"\n>>> PHASE 4: Service Mesh Tests ({args.mesh_type.upper()})")
            success = run_pytest(
                markers="phase4",
                extra_args=extra_args,
                mesh_type=args.mesh_type,
                kubeconfig=args.kubeconfig
            )
            results["phase4"] = "PASS" if success else "FAIL"

    if args.phase in ["all", "6", "compare"]:
        print("\n>>> PHASE 6: Comparative Analysis")
        success = run_pytest(
            markers="phase6",
            extra_args=extra_args,
            mesh_type=args.mesh_type,
            kubeconfig=args.kubeconfig
        )
        results["phase6"] = "PASS" if success else "FAIL"

    if args.phase in ["all", "7", "stress"]:
        print("\n>>> PHASE 7: Stress Tests")
        # Always include slow tests for stress testing
        stress_args = [a for a in extra_args if "not slow" not in a]

        success = run_pytest(
            markers="phase7",
            extra_args=stress_args,
            mesh_type=args.mesh_type,
            kubeconfig=args.kubeconfig
        )
        results["phase7"] = "PASS" if success else "FAIL"

    # Print summary
    end_time = time.time()
    duration = end_time - start_time

    print("\n" + "="*60)
    print("TEST SUMMARY")
    print("="*60)

    for phase, status in results.items():
        symbol = "✅" if status == "PASS" else "❌"
        print(f"{symbol} {phase.upper()}: {status}")

    print(f"\nTotal Duration: {duration:.2f} seconds")
    print("="*60)

    # Save summary
    summary = {
        "test_run": {
            "timestamp": time.time(),
            "duration_seconds": duration,
            "mesh_type": args.mesh_type,
            "phase": args.phase,
        },
        "results": results
    }

    results_dir = Path(__file__).parent.parent / "benchmarks" / "results"
    results_dir.mkdir(parents=True, exist_ok=True)

    summary_file = results_dir / "test_run_summary.json"
    with open(summary_file, "w") as f:
        json.dump(summary, f, indent=2)

    print(f"\nTest summary saved to: {summary_file}")
    print(f"HTML report: {results_dir / 'test_report.html'}")

    # Exit with failure if any tests failed
    if "FAIL" in results.values():
        sys.exit(1)


if __name__ == "__main__":
    main()
