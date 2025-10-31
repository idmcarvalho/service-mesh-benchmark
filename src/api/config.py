"""API configuration and global settings."""

from pathlib import Path
from typing import Dict

from src.api.settings import settings

# Project paths
PROJECT_ROOT = Path(__file__).parent.parent
BENCHMARKS_DIR = PROJECT_ROOT / "benchmarks" / "scripts"
RESULTS_DIR = PROJECT_ROOT / "benchmarks" / "results"
EBPF_PROBE_DIR = PROJECT_ROOT / "ebpf-probes" / "latency-probe"

# Benchmark script mapping
BENCHMARK_SCRIPTS = {
    "http": "http-load-test.sh",
    "grpc": "grpc-test.sh",
    "websocket": "websocket-test.sh",
    "ml": "ml-workload.sh",
}

# Service mesh component mappings
MESH_COMPONENTS = {
    "istio": ["istiod", "istio-ingressgateway"],
    "linkerd": ["linkerd-proxy", "linkerd-destination"],
    "cilium": ["cilium", "cilium-operator"],
    "consul": ["consul-server", "consul-connect-injector"],
}

# Initialize results directory
RESULTS_DIR.mkdir(parents=True, exist_ok=True)
