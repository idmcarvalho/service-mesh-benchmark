"""API request and response models."""

from datetime import datetime
from typing import Any, Dict, Optional

from pydantic import BaseModel, Field

from src.tests.models import MeshType


# ============================================================================
# Request Models
# ============================================================================


class BenchmarkRequest(BaseModel):
    """Request to start a benchmark test."""

    test_type: str = Field(
        description="Type of benchmark (http, grpc, websocket, ml)",
        pattern="^(http|grpc|websocket|ml)$",
    )
    mesh_type: MeshType = Field(
        default=MeshType.BASELINE, description="Service mesh type to test"
    )
    namespace: str = Field(
        default="default", description="Kubernetes namespace", pattern="^[a-z0-9-]+$"
    )
    duration: int = Field(default=60, ge=10, le=3600, description="Test duration in seconds")
    concurrent_connections: int = Field(
        default=100, ge=1, le=10000, description="Concurrent connections"
    )
    service_url: Optional[str] = Field(default=None, description="Optional service URL override")


class eBPFProbeRequest(BaseModel):
    """Request to start eBPF latency probe."""

    duration: int = Field(default=60, ge=10, le=3600, description="Probe duration in seconds")
    namespace: Optional[str] = Field(
        default=None, description="Filter by namespace", pattern="^[a-z0-9-]+$"
    )
    pod_filter: Optional[str] = Field(default=None, description="Filter by pod name pattern")
    output_format: str = Field(default="json", pattern="^(json|csv)$", description="Output format")


class ReportRequest(BaseModel):
    """Request to generate a report."""

    format: str = Field(default="html", pattern="^(html|json|csv)$", description="Report format")
    filter_mesh_type: Optional[MeshType] = Field(
        default=None, description="Filter results by mesh type"
    )
    filter_test_type: Optional[str] = Field(default=None, description="Filter by test type")


# ============================================================================
# Response Models
# ============================================================================


class BenchmarkResponse(BaseModel):
    """Response from starting a benchmark."""

    job_id: str = Field(description="Job ID for tracking")
    status: str = Field(description="Job status")
    message: str = Field(description="Status message")
    started_at: datetime = Field(description="Job start time")


class eBPFProbeResponse(BaseModel):
    """Response from eBPF probe."""

    job_id: str = Field(description="Job ID for tracking")
    status: str = Field(description="Probe status")
    message: str = Field(description="Status message")
    started_at: datetime = Field(description="Probe start time")


class JobStatus(BaseModel):
    """Status of a running or completed job."""

    job_id: str = Field(description="Job ID")
    status: str = Field(description="Job status: pending, running, completed, failed")
    test_type: str = Field(description="Type of benchmark")
    mesh_type: str = Field(description="Service mesh type")
    started_at: datetime = Field(description="Job start time")
    completed_at: Optional[datetime] = Field(default=None, description="Job completion time")
    result_file: Optional[str] = Field(default=None, description="Path to result file")
    error: Optional[str] = Field(default=None, description="Error message if failed")


class HealthResponse(BaseModel):
    """Health check response."""

    status: str = Field(description="Service status")
    version: str = Field(description="API version")
    timestamp: datetime = Field(description="Current timestamp")
    kubernetes_connected: bool = Field(description="Kubernetes connection status")
    active_jobs: int = Field(description="Number of active jobs")
