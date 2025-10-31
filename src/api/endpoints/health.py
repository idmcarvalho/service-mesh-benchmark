"""Health check and system status endpoints."""

from datetime import datetime
from pathlib import Path
from typing import Any, Dict

from fastapi import APIRouter
from kubernetes import client, config as k8s_config

from src.api.config import BENCHMARKS_DIR, EBPF_PROBE_DIR, RESULTS_DIR
from src.api.models import HealthResponse
from src.api.state import get_all_jobs

router = APIRouter(prefix="", tags=["Health"])


@router.get("/health", response_model=HealthResponse)
async def health_check() -> HealthResponse:
    """Health check endpoint."""
    k8s_connected = False
    try:
        k8s_config.load_kube_config()
        k8s_connected = True
    except Exception:
        pass

    all_jobs = await get_all_jobs()
    active_jobs = len([j for j in all_jobs.values() if j["status"] == "running"])

    return HealthResponse(
        status="healthy",
        version="1.0.0",
        timestamp=datetime.utcnow(),
        kubernetes_connected=k8s_connected,
        active_jobs=active_jobs,
    )


@router.get("/status")
async def system_status() -> Dict[str, Any]:
    """Get detailed system status including running jobs and available benchmarks."""
    # Get all jobs
    all_jobs = await get_all_jobs()

    # Check Kubernetes connectivity
    k8s_status: Dict[str, Any] = {"connected": False, "context": None, "version": None}
    try:
        k8s_config.load_kube_config()
        version_info = client.VersionApi().get_code()
        k8s_status.update({
            "connected": True,
            "version": f"{version_info.major}.{version_info.minor}",
        })
    except Exception as e:
        k8s_status["error"] = str(e)

    # List available benchmark scripts
    available_benchmarks = []
    if BENCHMARKS_DIR.exists():
        available_benchmarks = [
            f.stem
            for f in BENCHMARKS_DIR.glob("*.sh")
            if f.stem not in ["collect-metrics", "collect-ebpf-metrics"]
        ]

    # Check eBPF probe availability
    ebpf_probe_path = (
        EBPF_PROBE_DIR / "latency-probe-userspace" / "target" / "release" / "latency-probe"
    )
    ebpf_available = ebpf_probe_path.exists()

    return {
        "timestamp": datetime.utcnow().isoformat(),
        "kubernetes": k8s_status,
        "benchmarks": {
            "available": available_benchmarks,
            "scripts_dir": str(BENCHMARKS_DIR),
        },
        "ebpf": {
            "available": ebpf_available,
            "probe_path": str(ebpf_probe_path) if ebpf_available else None,
        },
        "jobs": {
            "total": len(all_jobs),
            "running": len([j for j in all_jobs.values() if j["status"] == "running"]),
            "completed": len([j for j in all_jobs.values() if j["status"] == "completed"]),
            "failed": len([j for j in all_jobs.values() if j["status"] == "failed"]),
        },
        "results_dir": str(RESULTS_DIR),
        "results_count": len(list(RESULTS_DIR.glob("*.json"))),
    }
