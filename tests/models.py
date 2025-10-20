"""Pydantic models for type-safe configuration and data structures."""

from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field, field_validator


class MeshType(str, Enum):
    """Supported service mesh types."""

    BASELINE = "baseline"
    ISTIO = "istio"
    CILIUM = "cilium"
    LINKERD = "linkerd"
    CONSUL = "consul"


class TestPhase(str, Enum):
    """Test execution phases."""

    PHASE1 = "phase1"  # Pre-deployment validation
    PHASE2 = "phase2"  # Infrastructure validation
    PHASE3 = "phase3"  # Baseline testing
    PHASE4 = "phase4"  # Service mesh testing
    PHASE6 = "phase6"  # Comparative analysis
    PHASE7 = "phase7"  # Stress testing


class TestConfig(BaseModel):
    """Global test configuration."""

    mesh_type: MeshType = Field(default=MeshType.BASELINE, description="Service mesh type to test")
    skip_infra: bool = Field(default=False, description="Skip infrastructure tests")
    kubeconfig: Path = Field(
        default=Path.home() / ".kube" / "config", description="Path to kubeconfig file"
    )
    test_duration: int = Field(default=60, gt=0, description="Test duration in seconds")
    concurrent_connections: int = Field(
        default=100, gt=0, description="Number of concurrent connections"
    )
    project_root: Path = Field(description="Project root directory")
    terraform_dir: Path = Field(description="Terraform directory")
    workloads_dir: Path = Field(description="Kubernetes workloads directory")
    benchmarks_dir: Path = Field(description="Benchmarks scripts directory")
    results_dir: Path = Field(description="Results output directory")

    @field_validator("kubeconfig", mode="before")
    @classmethod
    def expand_path(cls, v: Any) -> Path:
        """Expand ~ in paths."""
        if isinstance(v, str):
            return Path(v).expanduser()
        return v

    class Config:
        """Pydantic configuration."""

        use_enum_values = True


class LatencyMetrics(BaseModel):
    """Latency metrics for a test run."""

    min_ms: float = Field(ge=0, description="Minimum latency in milliseconds")
    max_ms: float = Field(ge=0, description="Maximum latency in milliseconds")
    avg_ms: float = Field(ge=0, description="Average latency in milliseconds")
    p50_ms: Optional[float] = Field(default=None, ge=0, description="50th percentile latency")
    p75_ms: Optional[float] = Field(default=None, ge=0, description="75th percentile latency")
    p90_ms: Optional[float] = Field(default=None, ge=0, description="90th percentile latency")
    p95_ms: Optional[float] = Field(default=None, ge=0, description="95th percentile latency")
    p99_ms: Optional[float] = Field(default=None, ge=0, description="99th percentile latency")
    p999_ms: Optional[float] = Field(default=None, ge=0, description="99.9th percentile latency")


class ThroughputMetrics(BaseModel):
    """Throughput metrics for a test run."""

    requests_per_sec: float = Field(ge=0, description="Requests per second")
    bytes_per_sec: Optional[float] = Field(default=None, ge=0, description="Bytes per second")
    total_requests: int = Field(ge=0, description="Total number of requests")
    successful_requests: int = Field(ge=0, description="Number of successful requests")
    failed_requests: int = Field(ge=0, description="Number of failed requests")

    @property
    def success_rate(self) -> float:
        """Calculate success rate percentage."""
        if self.total_requests == 0:
            return 0.0
        return (self.successful_requests / self.total_requests) * 100


class ResourceMetrics(BaseModel):
    """Resource utilization metrics."""

    cpu_millicores: float = Field(ge=0, description="CPU usage in millicores")
    memory_mb: float = Field(ge=0, description="Memory usage in megabytes")
    network_rx_mb: Optional[float] = Field(default=None, ge=0, description="Network RX in MB")
    network_tx_mb: Optional[float] = Field(default=None, ge=0, description="Network TX in MB")


class BenchmarkResult(BaseModel):
    """Complete benchmark result for a single test."""

    test_type: str = Field(description="Type of test (http, grpc, websocket, etc.)")
    mesh_type: MeshType = Field(description="Service mesh type")
    timestamp: datetime = Field(default_factory=datetime.utcnow, description="Test timestamp")
    duration_seconds: int = Field(gt=0, description="Test duration in seconds")
    latency: LatencyMetrics = Field(description="Latency metrics")
    throughput: ThroughputMetrics = Field(description="Throughput metrics")
    resources: Optional[ResourceMetrics] = Field(default=None, description="Resource metrics")
    metadata: Dict[str, Any] = Field(default_factory=dict, description="Additional metadata")

    class Config:
        """Pydantic configuration."""

        use_enum_values = True


class ComparisonResult(BaseModel):
    """Comparison between baseline and service mesh results."""

    baseline: BenchmarkResult = Field(description="Baseline test result")
    mesh: BenchmarkResult = Field(description="Service mesh test result")

    @property
    def latency_overhead_percent(self) -> float:
        """Calculate latency overhead percentage."""
        if self.baseline.latency.avg_ms == 0:
            return 0.0
        overhead = self.mesh.latency.avg_ms - self.baseline.latency.avg_ms
        return (overhead / self.baseline.latency.avg_ms) * 100

    @property
    def throughput_impact_percent(self) -> float:
        """Calculate throughput impact percentage (negative = degradation)."""
        if self.baseline.throughput.requests_per_sec == 0:
            return 0.0
        diff = self.mesh.throughput.requests_per_sec - self.baseline.throughput.requests_per_sec
        return (diff / self.baseline.throughput.requests_per_sec) * 100

    @property
    def cpu_overhead_millicores(self) -> float:
        """Calculate CPU overhead in millicores."""
        if not self.baseline.resources or not self.mesh.resources:
            return 0.0
        return self.mesh.resources.cpu_millicores - self.baseline.resources.cpu_millicores

    @property
    def memory_overhead_mb(self) -> float:
        """Calculate memory overhead in megabytes."""
        if not self.baseline.resources or not self.mesh.resources:
            return 0.0
        return self.mesh.resources.memory_mb - self.baseline.resources.memory_mb


class TestSummary(BaseModel):
    """Summary of all test results."""

    timestamp: datetime = Field(default_factory=datetime.utcnow, description="Summary timestamp")
    total_tests: int = Field(ge=0, description="Total number of tests run")
    passed_tests: int = Field(ge=0, description="Number of passed tests")
    failed_tests: int = Field(ge=0, description="Number of failed tests")
    skipped_tests: int = Field(ge=0, description="Number of skipped tests")
    duration_seconds: float = Field(ge=0, description="Total test duration in seconds")
    results: List[BenchmarkResult] = Field(default_factory=list, description="All test results")
    comparisons: List[ComparisonResult] = Field(
        default_factory=list, description="Comparison results"
    )

    @property
    def success_rate(self) -> float:
        """Calculate overall success rate percentage."""
        if self.total_tests == 0:
            return 0.0
        return (self.passed_tests / self.total_tests) * 100

    class Config:
        """Pydantic configuration."""

        use_enum_values = True


class KubernetesConfig(BaseModel):
    """Kubernetes cluster configuration."""

    context: str = Field(description="Kubernetes context name")
    namespace: str = Field(default="default", description="Default namespace")
    api_server: str = Field(description="Kubernetes API server URL")
    version: str = Field(description="Kubernetes version")


class TerraformOutput(BaseModel):
    """Terraform output values."""

    value: Any = Field(description="Output value")
    type: str = Field(description="Output type")
    sensitive: bool = Field(default=False, description="Whether output is sensitive")


class NodeInfo(BaseModel):
    """Kubernetes node information."""

    name: str = Field(description="Node name")
    status: str = Field(description="Node status")
    roles: List[str] = Field(default_factory=list, description="Node roles")
    cpu_capacity: str = Field(description="Total CPU capacity")
    memory_capacity: str = Field(description="Total memory capacity")
    cpu_allocatable: str = Field(description="Allocatable CPU")
    memory_allocatable: str = Field(description="Allocatable memory")
    kernel_version: str = Field(description="Kernel version")
    container_runtime: str = Field(description="Container runtime")


class PodInfo(BaseModel):
    """Kubernetes pod information."""

    name: str = Field(description="Pod name")
    namespace: str = Field(description="Pod namespace")
    status: str = Field(description="Pod status")
    node: Optional[str] = Field(default=None, description="Node name")
    ip: Optional[str] = Field(default=None, description="Pod IP")
    containers: List[str] = Field(default_factory=list, description="Container names")
    ready: bool = Field(default=False, description="Whether pod is ready")


class ServiceMeshStatus(BaseModel):
    """Service mesh installation status."""

    mesh_type: MeshType = Field(description="Service mesh type")
    installed: bool = Field(description="Whether mesh is installed")
    version: Optional[str] = Field(default=None, description="Mesh version")
    components: List[str] = Field(default_factory=list, description="Mesh components")
    healthy: bool = Field(default=False, description="Whether mesh is healthy")
    sidecar_injected: bool = Field(default=False, description="Whether sidecars are injected")

    class Config:
        """Pydantic configuration."""

        use_enum_values = True


class eBPFMetrics(BaseModel):
    """eBPF probe metrics."""

    timestamp: datetime = Field(description="Measurement timestamp")
    duration_seconds: int = Field(gt=0, description="Measurement duration")
    total_events: int = Field(ge=0, description="Total events captured")
    connections: Dict[str, Dict[str, Any]] = Field(
        default_factory=dict, description="Per-connection metrics"
    )
    histogram: Dict[str, int] = Field(default_factory=dict, description="Latency histogram")
    percentiles: LatencyMetrics = Field(description="Latency percentiles")
    event_type_breakdown: Dict[str, int] = Field(
        default_factory=dict, description="Event types breakdown"
    )

    class Config:
        """Pydantic configuration."""

        json_encoders = {datetime: lambda v: v.isoformat()}
