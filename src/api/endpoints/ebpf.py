"""eBPF probe control endpoints."""

import asyncio
from datetime import datetime
from pathlib import Path
from typing import Any, Dict

from fastapi import APIRouter, BackgroundTasks, HTTPException, status

from src.api.config import EBPF_PROBE_DIR, RESULTS_DIR
from src.api.models import eBPFProbeRequest, eBPFProbeResponse
from src.api.state import update_job, set_job, get_all_jobs

router = APIRouter(prefix="/ebpf", tags=["eBPF"])


async def run_ebpf_probe(job_id: str, request: eBPFProbeRequest) -> None:
    """Run eBPF latency probe in the background."""
    probe_path = (
        EBPF_PROBE_DIR / "daemon" / "target" / "release" / "latency-probe"
    )

    if not probe_path.exists():
        await update_job(job_id, {
            "status": "failed",
            "error": "eBPF probe not built",
            "completed_at": datetime.utcnow()
        })
        return

    try:
        await update_job(job_id, {"status": "running"})

        # Prepare output file
        timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
        output_file = RESULTS_DIR / f"ebpf_probe_{timestamp}.{request.output_format}"

        # Build command
        cmd = [
            "sudo",
            str(probe_path),
            "--duration",
            str(request.duration),
            "--output",
            str(output_file),
        ]

        if request.namespace:
            cmd.extend(["--namespace", request.namespace])
        if request.pod_filter:
            cmd.extend(["--pod-filter", request.pod_filter])

        # Run probe
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )

        stdout, stderr = await process.communicate()

        if process.returncode == 0:
            await update_job(job_id, {
                "result_file": str(output_file),
                "status": "completed"
            })
        else:
            await update_job(job_id, {
                "status": "failed",
                "error": stderr.decode() if stderr else "Unknown error"
            })

    except Exception as e:
        await update_job(job_id, {
            "status": "failed",
            "error": str(e)
        })

    finally:
        await update_job(job_id, {"completed_at": datetime.utcnow()})


@router.post("/probe/start", response_model=eBPFProbeResponse)
async def start_ebpf_probe(
    request: eBPFProbeRequest, background_tasks: BackgroundTasks
) -> eBPFProbeResponse:
    """Start eBPF latency probe."""
    probe_path = (
        EBPF_PROBE_DIR / "daemon" / "target" / "release" / "latency-probe"
    )

    if not probe_path.exists():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="eBPF probe not built. Run: cd src/probes && cargo build --release",
        )

    # Generate job ID
    job_id = f"ebpf_probe_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}"

    # Initialize job tracking
    started_at = datetime.utcnow()
    await set_job(job_id, {
        "job_id": job_id,
        "status": "pending",
        "test_type": "ebpf_probe",
        "mesh_type": "N/A",
        "started_at": started_at,
        "completed_at": None,
        "result_file": None,
        "error": None,
    })

    # Start probe in background
    background_tasks.add_task(run_ebpf_probe, job_id, request)

    return eBPFProbeResponse(
        job_id=job_id,
        status="pending",
        message="eBPF probe started",
        started_at=started_at,
    )


@router.get("/probe/status")
async def ebpf_probe_status() -> Dict[str, Any]:
    """Check eBPF probe availability and status."""
    probe_path = (
        EBPF_PROBE_DIR / "daemon" / "target" / "release" / "latency-probe"
    )

    available = probe_path.exists()
    all_jobs = await get_all_jobs()
    running_probes = [
        j
        for j in all_jobs.values()
        if j["test_type"] == "ebpf_probe" and j["status"] == "running"
    ]

    return {
        "available": available,
        "probe_path": str(probe_path),
        "running_probes": len(running_probes),
        "build_instructions": "Run: cd src/probes && cargo build --release"
        if not available
        else None,
    }
