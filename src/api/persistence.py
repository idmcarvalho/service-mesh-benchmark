"""JSON-based job persistence for simple file-based backup.

This module provides optional persistence of benchmark jobs to JSON files,
allowing job history to survive API restarts without requiring a database.
"""

import json
import asyncio
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

from src.api.config import RESULTS_DIR


class JobPersistence:
    """Simple JSON file-based job persistence."""

    def __init__(self, storage_dir: Optional[Path] = None):
        """Initialize job persistence.

        Args:
            storage_dir: Directory to store job files. Defaults to RESULTS_DIR.
        """
        self.storage_dir = storage_dir or RESULTS_DIR
        self.jobs_file = self.storage_dir / "jobs_history.json"
        self._lock = asyncio.Lock()

        # Ensure directory exists
        self.storage_dir.mkdir(parents=True, exist_ok=True)

    async def save_job(self, job_id: str, job_data: Dict[str, Any]) -> None:
        """Save a single job to persistent storage.

        Args:
            job_id: Unique job identifier
            job_data: Job data dictionary
        """
        async with self._lock:
            # Load existing jobs
            jobs = await self._load_jobs_dict()

            # Add or update job
            # Convert datetime objects to ISO format strings
            job_copy = self._serialize_job(job_data)
            jobs[job_id] = job_copy

            # Save back to file
            await self._save_jobs_dict(jobs)

    async def load_job(self, job_id: str) -> Optional[Dict[str, Any]]:
        """Load a single job from persistent storage.

        Args:
            job_id: Unique job identifier

        Returns:
            Job data dictionary or None if not found
        """
        async with self._lock:
            jobs = await self._load_jobs_dict()
            job_data = jobs.get(job_id)

            if job_data:
                return self._deserialize_job(job_data)
            return None

    async def load_all_jobs(self) -> Dict[str, Dict[str, Any]]:
        """Load all jobs from persistent storage.

        Returns:
            Dictionary mapping job IDs to job data
        """
        async with self._lock:
            jobs = await self._load_jobs_dict()
            return {
                job_id: self._deserialize_job(job_data)
                for job_id, job_data in jobs.items()
            }

    async def delete_job(self, job_id: str) -> bool:
        """Delete a job from persistent storage.

        Args:
            job_id: Unique job identifier

        Returns:
            True if job was deleted, False if not found
        """
        async with self._lock:
            jobs = await self._load_jobs_dict()

            if job_id in jobs:
                del jobs[job_id]
                await self._save_jobs_dict(jobs)
                return True

            return False

    async def cleanup_old_jobs(self, days: int = 30) -> int:
        """Remove jobs older than specified days.

        Args:
            days: Number of days to retain jobs

        Returns:
            Number of jobs deleted
        """
        from datetime import timedelta

        cutoff_date = datetime.utcnow() - timedelta(days=days)
        deleted_count = 0

        async with self._lock:
            jobs = await self._load_jobs_dict()
            initial_count = len(jobs)

            # Filter out old completed/failed jobs
            jobs_to_keep = {}
            for job_id, job_data in jobs.items():
                completed_at = job_data.get("completed_at")
                status = job_data.get("status")

                # Keep if not completed, or completed recently
                if not completed_at or status not in ["completed", "failed"]:
                    jobs_to_keep[job_id] = job_data
                else:
                    try:
                        completed_dt = datetime.fromisoformat(
                            completed_at.replace("Z", "+00:00")
                        )
                        if completed_dt > cutoff_date:
                            jobs_to_keep[job_id] = job_data
                    except (ValueError, AttributeError):
                        # Keep if we can't parse date
                        jobs_to_keep[job_id] = job_data

            deleted_count = initial_count - len(jobs_to_keep)

            if deleted_count > 0:
                await self._save_jobs_dict(jobs_to_keep)

        return deleted_count

    async def get_stats(self) -> Dict[str, Any]:
        """Get statistics about persisted jobs.

        Returns:
            Dictionary with job statistics
        """
        async with self._lock:
            jobs = await self._load_jobs_dict()

            stats = {
                "total_jobs": len(jobs),
                "by_status": {},
                "by_test_type": {},
                "by_mesh_type": {},
                "storage_file": str(self.jobs_file),
                "file_size_bytes": 0,
            }

            # Count by categories
            for job_data in jobs.values():
                status = job_data.get("status", "unknown")
                test_type = job_data.get("test_type", "unknown")
                mesh_type = job_data.get("mesh_type", "unknown")

                stats["by_status"][status] = stats["by_status"].get(status, 0) + 1
                stats["by_test_type"][test_type] = (
                    stats["by_test_type"].get(test_type, 0) + 1
                )
                stats["by_mesh_type"][mesh_type] = (
                    stats["by_mesh_type"].get(mesh_type, 0) + 1
                )

            # Get file size if it exists
            if self.jobs_file.exists():
                stats["file_size_bytes"] = self.jobs_file.stat().st_size

            return stats

    # Private helper methods

    async def _load_jobs_dict(self) -> Dict[str, Dict[str, Any]]:
        """Load jobs dictionary from file."""
        if not self.jobs_file.exists():
            return {}

        try:
            with open(self.jobs_file, "r") as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError) as e:
            print(f"Warning: Failed to load jobs file: {e}")
            # Backup corrupted file
            if self.jobs_file.exists():
                backup_file = self.jobs_file.with_suffix(
                    f".backup.{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.json"
                )
                self.jobs_file.rename(backup_file)
                print(f"Corrupted file backed up to: {backup_file}")
            return {}

    async def _save_jobs_dict(self, jobs: Dict[str, Dict[str, Any]]) -> None:
        """Save jobs dictionary to file."""
        try:
            # Write to temporary file first
            temp_file = self.jobs_file.with_suffix(".tmp")
            with open(temp_file, "w") as f:
                json.dump(jobs, f, indent=2, default=str)

            # Atomic rename
            temp_file.replace(self.jobs_file)
        except IOError as e:
            print(f"Error: Failed to save jobs file: {e}")

    def _serialize_job(self, job_data: Dict[str, Any]) -> Dict[str, Any]:
        """Convert job data to JSON-serializable format."""
        serialized = job_data.copy()

        # Convert datetime objects to ISO format strings
        for key in ["started_at", "completed_at", "created_at"]:
            if key in serialized and serialized[key] is not None:
                if isinstance(serialized[key], datetime):
                    serialized[key] = serialized[key].isoformat() + "Z"

        return serialized

    def _deserialize_job(self, job_data: Dict[str, Any]) -> Dict[str, Any]:
        """Convert stored job data back to runtime format."""
        # For now, keep as-is since we store as ISO strings
        # Could convert back to datetime objects if needed
        return job_data.copy()


# Global persistence instance
_persistence: Optional[JobPersistence] = None


def get_persistence() -> JobPersistence:
    """Get the global job persistence instance.

    Returns:
        JobPersistence instance
    """
    global _persistence
    if _persistence is None:
        _persistence = JobPersistence()
    return _persistence


async def sync_job_to_persistence(job_id: str, job_data: Dict[str, Any]) -> None:
    """Convenience function to save a job to persistence.

    Args:
        job_id: Job identifier
        job_data: Job data dictionary
    """
    persistence = get_persistence()
    await persistence.save_job(job_id, job_data)


async def load_jobs_from_persistence() -> Dict[str, Dict[str, Any]]:
    """Convenience function to load all jobs from persistence.

    Returns:
        Dictionary of all persisted jobs
    """
    persistence = get_persistence()
    return await persistence.load_all_jobs()
