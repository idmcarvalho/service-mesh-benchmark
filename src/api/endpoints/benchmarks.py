"""Benchmark execution endpoints."""

import asyncio
import json
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, BackgroundTasks, HTTPException, Query, status

from src.api.config import BENCHMARK_SCRIPTS, BENCHMARKS_DIR, RESULTS_DIR
from src.api.models import BenchmarkRequest, BenchmarkResponse, JobStatus
from src.api.state import running_jobs

router = APIRouter(prefix="/benchmarks", tags=["Benchmarks"])


async def run_benchmark_script(
    job_id: str,
    script_name: str,
    env_vars: Dict[str, str],
) -> None:
    """Run a benchmark script in the background."""
    script_path = BENCHMARKS_DIR / script_name

    if not script_path.exists():
        running_jobs[job_id]["status"] = "failed"
        running_jobs[job_id]["error"] = f"Script not found: {script_name}"
        running_jobs[job_id]["completed_at"] = datetime.utcnow()
        return

    try:
        # Update status
        running_jobs[job_id]["status"] = "running"

        # Prepare environment
        env: Dict[str, str] = {}
        env.update(env_vars)

        # Run the script
        process = await asyncio.create_subprocess_exec(
            "bash",
            str(script_path),
            env=env,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=BENCHMARKS_DIR,
        )

        stdout, stderr = await process.communicate()

        if process.returncode == 0:
            # Find the most recent result file
            results_files = list(RESULTS_DIR.glob("*.json"))
            if results_files:
                latest_result = max(results_files, key=lambda p: p.stat().st_mtime)
                running_jobs[job_id]["result_file"] = str(latest_result)
                running_jobs[job_id]["status"] = "completed"
            else:
                running_jobs[job_id]["status"] = "failed"
                running_jobs[job_id]["error"] = "No result file generated"
        else:
            running_jobs[job_id]["status"] = "failed"
            running_jobs[job_id]["error"] = stderr.decode() if stderr else "Unknown error"

    except Exception as e:
        running_jobs[job_id]["status"] = "failed"
        running_jobs[job_id]["error"] = str(e)

    finally:
        running_jobs[job_id]["completed_at"] = datetime.utcnow()


@router.post("/start", response_model=BenchmarkResponse)
async def start_benchmark(
    request: BenchmarkRequest, background_tasks: BackgroundTasks
) -> BenchmarkResponse:
    """Start a benchmark test."""
    # Generate job ID
    job_id = f"{request.test_type}_{request.mesh_type}_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}"

    # Get script name
    script_name = BENCHMARK_SCRIPTS.get(request.test_type)
    if not script_name:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unknown test type: {request.test_type}",
        )

    # Prepare environment variables
    env_vars = {
        "MESH_TYPE": request.mesh_type.value,
        "NAMESPACE": request.namespace,
        "TEST_DURATION": str(request.duration),
        "CONCURRENT_CONNECTIONS": str(request.concurrent_connections),
        "RESULTS_DIR": str(RESULTS_DIR),
    }

    if request.service_url:
        env_vars["SERVICE_URL"] = request.service_url

    # Initialize job tracking
    started_at = datetime.utcnow()
    running_jobs[job_id] = {
        "job_id": job_id,
        "status": "pending",
        "test_type": request.test_type,
        "mesh_type": request.mesh_type.value,
        "started_at": started_at,
        "completed_at": None,
        "result_file": None,
        "error": None,
    }

    # Start benchmark in background
    background_tasks.add_task(run_benchmark_script, job_id, script_name, env_vars)

    return BenchmarkResponse(
        job_id=job_id,
        status="pending",
        message=f"Benchmark {request.test_type} started",
        started_at=started_at,
    )


@router.get("/jobs", response_model=List[JobStatus])
async def list_jobs(
    status_filter: Optional[str] = Query(None, description="Filter by status"),
    test_type_filter: Optional[str] = Query(None, description="Filter by test type"),
) -> List[JobStatus]:
    """List all benchmark jobs."""
    jobs = list(running_jobs.values())

    # Apply filters
    if status_filter:
        jobs = [j for j in jobs if j["status"] == status_filter]
    if test_type_filter:
        jobs = [j for j in jobs if j["test_type"] == test_type_filter]

    return [JobStatus(**job) for job in jobs]


@router.get("/jobs/{job_id}", response_model=JobStatus)
async def get_job_status(job_id: str) -> JobStatus:
    """Get status of a specific job."""
    if job_id not in running_jobs:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=f"Job not found: {job_id}"
        )

    return JobStatus(**running_jobs[job_id])


@router.get("/jobs/{job_id}/result")
async def get_job_result(job_id: str) -> Dict[str, Any]:
    """Get the result of a completed job."""
    if job_id not in running_jobs:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=f"Job not found: {job_id}"
        )

    job = running_jobs[job_id]

    if job["status"] != "completed":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Job not completed. Current status: {job['status']}",
        )

    if not job["result_file"]:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Result file not found"
        )

    result_path = Path(job["result_file"])
    if not result_path.exists():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Result file does not exist"
        )

    with open(result_path) as f:
        return json.load(f)


@router.delete("/jobs/{job_id}")
async def cancel_job(job_id: str) -> Dict[str, str]:
    """Cancel a running job (if possible) or remove from tracking."""
    if job_id not in running_jobs:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=f"Job not found: {job_id}"
        )

    job = running_jobs[job_id]

    if job["status"] == "running":
        # Note: Canceling running subprocess is complex - for now just mark as failed
        running_jobs[job_id]["status"] = "failed"
        running_jobs[job_id]["error"] = "Cancelled by user"
        running_jobs[job_id]["completed_at"] = datetime.utcnow()

    # Remove from tracking
    del running_jobs[job_id]

    return {"message": f"Job {job_id} removed"}
