"""Shared application state for tracking jobs."""

import asyncio
from typing import Any, Dict

# Track running jobs across all endpoints
# Using asyncio.Lock to prevent race conditions when multiple
# async tasks modify the dictionary concurrently
running_jobs: Dict[str, Dict[str, Any]] = {}
_jobs_lock = asyncio.Lock()


async def get_job(job_id: str) -> Dict[str, Any] | None:
    """Get a job by ID in a thread-safe manner."""
    async with _jobs_lock:
        return running_jobs.get(job_id)


async def set_job(job_id: str, job_data: Dict[str, Any]) -> None:
    """Set/create a job in a thread-safe manner."""
    async with _jobs_lock:
        running_jobs[job_id] = job_data


async def update_job(job_id: str, updates: Dict[str, Any]) -> None:
    """Update a job's fields in a thread-safe manner."""
    async with _jobs_lock:
        if job_id in running_jobs:
            running_jobs[job_id].update(updates)


async def delete_job(job_id: str) -> bool:
    """Delete a job in a thread-safe manner."""
    async with _jobs_lock:
        if job_id in running_jobs:
            del running_jobs[job_id]
            return True
        return False


async def get_all_jobs() -> Dict[str, Dict[str, Any]]:
    """Get a copy of all jobs in a thread-safe manner."""
    async with _jobs_lock:
        return running_jobs.copy()
