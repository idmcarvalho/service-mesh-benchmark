"""Metrics and results endpoints."""

import json
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, HTTPException, Query, status

from src.api.config import RESULTS_DIR
from tests.models import MeshType

router = APIRouter(prefix="/metrics", tags=["Metrics"])


@router.get("/results")
async def list_results(
    mesh_type: Optional[MeshType] = Query(None, description="Filter by mesh type"),
    test_type: Optional[str] = Query(None, description="Filter by test type"),
    limit: int = Query(50, ge=1, le=500, description="Maximum results to return"),
) -> List[Dict[str, Any]]:
    """List available benchmark results."""
    results = []

    # Load all JSON result files
    json_files = sorted(RESULTS_DIR.glob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True)

    for json_file in json_files:
        try:
            with open(json_file) as f:
                data = json.load(f)

            # Apply filters
            if mesh_type and data.get("mesh_type") != mesh_type.value:
                continue
            if test_type and data.get("test_type") != test_type:
                continue

            results.append({
                "file": json_file.name,
                "test_type": data.get("test_type"),
                "mesh_type": data.get("mesh_type"),
                "timestamp": data.get("timestamp"),
                "metrics": data.get("metrics", {}),
            })

            if len(results) >= limit:
                break

        except (json.JSONDecodeError, KeyError):
            continue

    return results


@router.get("/results/{filename}")
async def get_result_file(filename: str) -> Dict[str, Any]:
    """Get a specific result file."""
    # Sanitize filename to prevent directory traversal
    if "/" in filename or ".." in filename:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid filename"
        )

    result_path = RESULTS_DIR / filename
    if not result_path.exists():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=f"Result file not found: {filename}"
        )

    with open(result_path) as f:
        return json.load(f)


@router.get("/summary")
async def metrics_summary(
    mesh_type: Optional[MeshType] = Query(None, description="Filter by mesh type"),
) -> Dict[str, Any]:
    """Get summary statistics of all results."""
    results = []

    for json_file in RESULTS_DIR.glob("*.json"):
        try:
            with open(json_file) as f:
                data = json.load(f)

            if mesh_type and data.get("mesh_type") != mesh_type.value:
                continue

            results.append(data)

        except (json.JSONDecodeError, KeyError):
            continue

    # Calculate aggregated metrics
    total_tests = len(results)
    by_mesh: Dict[str, int] = {}
    by_test_type: Dict[str, int] = {}

    for result in results:
        m_type = result.get("mesh_type", "unknown")
        t_type = result.get("test_type", "unknown")

        by_mesh[m_type] = by_mesh.get(m_type, 0) + 1
        by_test_type[t_type] = by_test_type.get(t_type, 0) + 1

    return {
        "total_tests": total_tests,
        "by_mesh_type": by_mesh,
        "by_test_type": by_test_type,
        "results_dir": str(RESULTS_DIR),
    }
