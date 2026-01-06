"""Centralized path configuration for the entire project.

This module provides a single source of truth for all project paths,
eliminating duplication between API config, tests, and other components.
"""

from pathlib import Path


class ProjectPaths:
    """Project directory structure paths."""

    def __init__(self, base_path: Path | None = None):
        """Initialize project paths.

        Args:
            base_path: Optional base path for the project root.
                      If None, auto-detects from this file's location.
        """
        if base_path is None:
            # Auto-detect: go up from src/common/paths.py to repository root
            self.root = Path(__file__).parent.parent.parent
        else:
            self.root = base_path

        # Source directories
        self.src = self.root / "src"
        self.api = self.src / "api"
        self.tests = self.src / "tests"
        self.probes = self.src / "probes"

        # Workload directories
        self.workloads = self.root / "workloads"
        self.kubernetes = self.workloads / "kubernetes"
        self.kubernetes_workloads = self.kubernetes / "workloads"
        self.kubernetes_rbac = self.kubernetes / "rbac"
        self.kubernetes_policies = self.kubernetes / "network-policies"

        # Scripts directories
        self.scripts = self.workloads / "scripts"
        self.script_runners = self.scripts / "runners"
        self.script_metrics = self.scripts / "metrics"
        self.script_validation = self.scripts / "validation"
        self.results = self.scripts / "results"

        # Docker directories
        self.docker = self.workloads / "docker"

        # Infrastructure directories
        self.infrastructure = self.root / "infrastructure"
        self.terraform = self.infrastructure / "terraform"
        self.terraform_oracle = self.terraform / "oracle-cloud"
        self.ansible = self.infrastructure / "ansible"

        # Configuration directories
        self.config = self.root / "config"
        self.config_local = self.config / "local"
        self.config_monitoring = self.config / "monitoring"
        self.config_templates = self.config / "templates"

        # Documentation directories
        self.docs = self.root / "docs"

        # Tools directories
        self.tools = self.root / "tools"
        self.tools_scripts = self.tools / "scripts"
        self.ci = self.tools / "ci"

        # Development directories
        self.develop = self.root / "develop"

        # eBPF probe specific paths
        self.ebpf_latency = self.probes / "latency"
        self.ebpf_kernel = self.ebpf_latency / "kernel"
        self.ebpf_daemon = self.ebpf_latency / "daemon"
        self.ebpf_binary = self.ebpf_daemon / "target" / "release" / "latency-probe"

    def ensure_results_dir(self) -> None:
        """Ensure results directory exists."""
        self.results.mkdir(parents=True, exist_ok=True)

    def validate(self) -> list[str]:
        """Validate that critical paths exist.

        Returns:
            List of missing critical paths (empty if all exist).
        """
        critical_paths = [
            ("Root directory", self.root),
            ("Source directory", self.src),
            ("Workloads directory", self.workloads),
            ("Infrastructure directory", self.infrastructure),
        ]

        missing = []
        for name, path in critical_paths:
            if not path.exists():
                missing.append(f"{name}: {path}")

        return missing


# Global singleton instance
paths = ProjectPaths()


# Backward compatibility exports
PROJECT_ROOT = paths.root
BENCHMARKS_DIR = paths.script_runners
RESULTS_DIR = paths.results
EBPF_PROBE_DIR = paths.ebpf_latency
TERRAFORM_DIR = paths.terraform_oracle
WORKLOADS_DIR = paths.kubernetes_workloads
