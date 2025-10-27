"""Shared application state for tracking jobs."""

from typing import Any, Dict

# Track running jobs across all endpoints
running_jobs: Dict[str, Dict[str, Any]] = {}
