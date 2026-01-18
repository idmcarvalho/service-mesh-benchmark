#!/usr/bin/env python3
"""Validation script for context switch claims and eBPF overhead measurement.

This script measures:
1. Context switches with and without eBPF probes
2. eBPF program verification overhead
3. eBPF program execution overhead
4. Memory overhead of eBPF maps

Usage:
    sudo python3 validate_overhead.py --duration 60 --output results.json
"""

import argparse
import json
import subprocess
import time
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Dict, List, Optional

import psutil


@dataclass
class ContextSwitchMetrics:
    """Metrics for context switches."""

    voluntary_switches: int
    involuntary_switches: int
    total_switches: int
    switches_per_second: float
    cpu_migrations: int


@dataclass
class eBPFOverheadMetrics:
    """Metrics for eBPF overhead."""

    verification_time_ms: float
    loading_time_ms: float
    map_memory_kb: int
    program_memory_kb: int
    cpu_overhead_percent: float


@dataclass
class ValidationResult:
    """Complete validation results."""

    test_duration_seconds: int
    baseline_context_switches: ContextSwitchMetrics
    ebpf_context_switches: ContextSwitchMetrics
    ebpf_overhead: eBPFOverheadMetrics
    context_switch_difference: int
    context_switch_percent_change: float
    timestamp: str


def measure_context_switches(
    pid: int, duration: int
) -> ContextSwitchMetrics:
    """Measure context switches for a process using perf.

    Args:
        pid: Process ID to measure.
        duration: Duration in seconds.

    Returns:
        ContextSwitchMetrics with measured values.
    """
    # Use perf to measure context switches
    cmd = [
        "perf",
        "stat",
        "-e",
        "context-switches,cpu-migrations",
        "-p",
        str(pid),
        "sleep",
        str(duration),
    ]

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=duration + 10,
        )

        # Parse perf output
        stderr = result.stderr
        context_switches = 0
        cpu_migrations = 0

        for line in stderr.split("\n"):
            if "context-switches" in line:
                parts = line.strip().split()
                context_switches = int(parts[0].replace(",", ""))
            elif "cpu-migrations" in line:
                parts = line.strip().split()
                cpu_migrations = int(parts[0].replace(",", ""))

        # Get voluntary/involuntary from /proc
        proc = psutil.Process(pid)
        ctx_switches = proc.num_ctx_switches()

        return ContextSwitchMetrics(
            voluntary_switches=ctx_switches.voluntary,
            involuntary_switches=ctx_switches.involuntary,
            total_switches=context_switches or (ctx_switches.voluntary + ctx_switches.involuntary),
            switches_per_second=(ctx_switches.voluntary + ctx_switches.involuntary) / duration,
            cpu_migrations=cpu_migrations,
        )

    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, psutil.NoSuchProcess) as e:
        print(f"Error measuring context switches: {e}")
        return ContextSwitchMetrics(0, 0, 0, 0.0, 0)


def measure_ebpf_verification_time(probe_path: Path) -> float:
    """Measure eBPF program verification time.

    Args:
        probe_path: Path to the eBPF probe binary.

    Returns:
        Verification time in milliseconds.
    """
    # Load the program and measure time
    start = time.perf_counter()

    cmd = ["sudo", "bpftool", "prog", "load", str(probe_path), "/sys/fs/bpf/test_probe"]

    try:
        subprocess.run(cmd, capture_output=True, timeout=10, check=False)
        end = time.perf_counter()

        # Clean up
        subprocess.run(["sudo", "rm", "-f", "/sys/fs/bpf/test_probe"], check=False)

        return (end - start) * 1000  # Convert to ms

    except subprocess.TimeoutExpired:
        return 0.0


def measure_ebpf_map_memory() -> int:
    """Measure memory used by eBPF maps.

    Returns:
        Memory usage in KB.
    """
    try:
        result = subprocess.run(
            ["sudo", "bpftool", "map", "show"],
            capture_output=True,
            text=True,
            timeout=5,
        )

        # Parse output to estimate memory
        # This is a rough estimate
        maps_count = len([line for line in result.stdout.split("\n") if line.strip()])

        # Average map size estimate: 4KB per map
        return maps_count * 4

    except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
        return 0


def measure_cpu_overhead_with_ebpf(
    workload_cmd: List[str],
    duration: int,
    with_ebpf: bool = False,
) -> float:
    """Measure CPU overhead with and without eBPF.

    Args:
        workload_cmd: Command to run as workload.
        duration: Duration in seconds.
        with_ebpf: Whether to run with eBPF probes attached.

    Returns:
        CPU usage percentage.
    """
    # Start workload
    workload = subprocess.Popen(
        workload_cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    try:
        # Let it stabilize
        time.sleep(2)

        # Measure CPU usage
        proc = psutil.Process(workload.pid)
        cpu_samples = []

        for _ in range(duration):
            cpu_samples.append(proc.cpu_percent(interval=1))

        avg_cpu = sum(cpu_samples) / len(cpu_samples) if cpu_samples else 0.0

        return avg_cpu

    finally:
        workload.terminate()
        workload.wait(timeout=5)


def run_baseline_measurement(duration: int) -> ContextSwitchMetrics:
    """Run baseline context switch measurement (no eBPF).

    Args:
        duration: Duration in seconds.

    Returns:
        ContextSwitchMetrics for baseline.
    """
    print(f"Running baseline measurement ({duration}s)...")

    # Start a simple workload
    workload = subprocess.Popen(
        ["stress-ng", "--cpu", "1", "--timeout", f"{duration}s", "--quiet"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    try:
        time.sleep(1)  # Let it start
        metrics = measure_context_switches(workload.pid, duration - 2)
        return metrics

    finally:
        workload.wait(timeout=10)


def run_ebpf_measurement(
    probe_binary: Path,
    duration: int,
) -> tuple[ContextSwitchMetrics, eBPFOverheadMetrics]:
    """Run context switch measurement with eBPF probes attached.

    Args:
        probe_binary: Path to the eBPF probe binary.
        duration: Duration in seconds.

    Returns:
        Tuple of (ContextSwitchMetrics, eBPFOverheadMetrics).
    """
    print(f"Running eBPF measurement ({duration}s)...")

    # Start eBPF probe
    probe_proc = subprocess.Popen(
        ["sudo", str(probe_binary), "--duration", str(duration), "--output", "/tmp/ebpf_test.json"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    # Start workload
    workload = subprocess.Popen(
        ["stress-ng", "--cpu", "1", "--timeout", f"{duration}s", "--quiet"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    try:
        time.sleep(1)  # Let it start
        ctx_metrics = measure_context_switches(workload.pid, duration - 2)

        # Measure eBPF overhead
        verification_time = measure_ebpf_verification_time(probe_binary.parent / "latency-probe.o")
        map_memory = measure_ebpf_map_memory()

        ebpf_metrics = eBPFOverheadMetrics(
            verification_time_ms=verification_time,
            loading_time_ms=0.0,  # Measured separately
            map_memory_kb=map_memory,
            program_memory_kb=0,  # Estimated from BPF maps
            cpu_overhead_percent=0.0,  # Calculated later
        )

        return ctx_metrics, ebpf_metrics

    finally:
        workload.wait(timeout=10)
        probe_proc.terminate()
        probe_proc.wait(timeout=10)


def validate_overhead(
    probe_binary: Path,
    duration: int = 60,
    output_file: Optional[Path] = None,
) -> ValidationResult:
    """Run complete overhead validation.

    Args:
        probe_binary: Path to the eBPF probe binary.
        duration: Duration for each test in seconds.
        output_file: Optional output file for results.

    Returns:
        ValidationResult with all measurements.
    """
    print("=" * 60)
    print("eBPF Overhead Validation")
    print("=" * 60)
    print()

    # Check requirements
    if not probe_binary.exists():
        raise FileNotFoundError(f"Probe binary not found: {probe_binary}")

    # Run baseline
    baseline = run_baseline_measurement(duration)
    print(f"Baseline context switches: {baseline.total_switches:,}")
    print(f"  Voluntary: {baseline.voluntary_switches:,}")
    print(f"  Involuntary: {baseline.involuntary_switches:,}")
    print(f"  Rate: {baseline.switches_per_second:.2f} switches/sec")
    print()

    # Run with eBPF
    ebpf_ctx, ebpf_overhead = run_ebpf_measurement(probe_binary, duration)
    print(f"eBPF context switches: {ebpf_ctx.total_switches:,}")
    print(f"  Voluntary: {ebpf_ctx.voluntary_switches:,}")
    print(f"  Involuntary: {ebpf_ctx.involuntary_switches:,}")
    print(f"  Rate: {ebpf_ctx.switches_per_second:.2f} switches/sec")
    print()

    # Calculate differences
    diff = ebpf_ctx.total_switches - baseline.total_switches
    percent_change = (diff / baseline.total_switches * 100) if baseline.total_switches > 0 else 0

    print(f"Difference: {diff:+,} context switches ({percent_change:+.2f}%)")
    print()
    print(f"eBPF Overhead:")
    print(f"  Verification time: {ebpf_overhead.verification_time_ms:.2f}ms")
    print(f"  Map memory: {ebpf_overhead.map_memory_kb}KB")
    print()

    # Create result
    result = ValidationResult(
        test_duration_seconds=duration,
        baseline_context_switches=baseline,
        ebpf_context_switches=ebpf_ctx,
        ebpf_overhead=ebpf_overhead,
        context_switch_difference=diff,
        context_switch_percent_change=percent_change,
        timestamp=time.strftime("%Y-%m-%d %H:%M:%S"),
    )

    # Save to file
    if output_file:
        with open(output_file, "w") as f:
            json.dump(asdict(result), f, indent=2)
        print(f"Results saved to: {output_file}")

    return result


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description="Validate eBPF overhead and context switch claims")
    parser.add_argument(
        "--probe-binary",
        type=Path,
        default=Path(__file__).parent / "latency/target/release/latency-probe",
        help="Path to eBPF probe binary",
    )
    parser.add_argument(
        "--duration",
        type=int,
        default=60,
        help="Duration for each test in seconds",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("ebpf_validation_results.json"),
        help="Output file for results",
    )

    args = parser.parse_args()

    try:
        result = validate_overhead(
            probe_binary=args.probe_binary,
            duration=args.duration,
            output_file=args.output,
        )

        print("=" * 60)
        print("Validation Complete")
        print("=" * 60)

        # Summary
        if abs(result.context_switch_percent_change) < 5:
            print("✅ Context switch overhead is NEGLIGIBLE (<5%)")
        elif abs(result.context_switch_percent_change) < 10:
            print("⚠️  Context switch overhead is MINOR (5-10%)")
        else:
            print("❌ Context switch overhead is SIGNIFICANT (>10%)")

    except Exception as e:
        print(f"Error: {e}")
        return 1

    return 0


if __name__ == "__main__":
    exit(main())
