"""API configuration and global settings."""

from typing import Dict

from src.api.settings import settings
from src.common.paths import paths

# Import paths from centralized configuration
PROJECT_ROOT = paths.root
BENCHMARKS_DIR = paths.script_runners
RESULTS_DIR = paths.results
EBPF_PROBE_DIR = paths.ebpf_latency

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
paths.ensure_results_dir()
