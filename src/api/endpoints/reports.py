"""Report generation endpoints."""

import subprocess
from datetime import datetime
from typing import Any, Dict, List

from fastapi import APIRouter, BackgroundTasks, HTTPException, status
from fastapi.responses import FileResponse

from src.api.config import PROJECT_ROOT, RESULTS_DIR
from src.api.models import ReportRequest

router = APIRouter(prefix="/reports", tags=["Reports"])


@router.post("/generate")
async def generate_report(
    request: ReportRequest, background_tasks: BackgroundTasks
) -> Dict[str, Any]:
    """Generate a benchmark report."""
    # Build command
    timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    output_filename = f"report_{timestamp}.{request.format}"
    output_path = RESULTS_DIR / output_filename

    cmd = [
        "python3",
        str(PROJECT_ROOT / "generate-report.py"),
        "--results-dir",
        str(RESULTS_DIR),
        "--format",
        request.format,
        "--output",
        str(output_path),
    ]

    try:
        # Run synchronously for now (could be backgrounded)
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True,
            timeout=300,
        )

        # Verify the generated report exists
        if output_path.exists():
            return {
                "status": "completed",
                "report_file": output_filename,
                "format": request.format,
                "download_url": f"/reports/download/{output_filename}",
            }
        else:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Report generated but file not found",
            )

    except subprocess.TimeoutExpired:
        raise HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT, detail="Report generation timeout"
        )
    except subprocess.CalledProcessError as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Report generation failed: {e.stderr}",
        )


@router.get("/list")
async def list_reports() -> List[Dict[str, Any]]:
    """List generated reports."""
    reports = []

    for ext in ["html", "json", "csv"]:
        for report_file in RESULTS_DIR.glob(f"report_*.{ext}"):
            reports.append({
                "filename": report_file.name,
                "format": ext,
                "size_bytes": report_file.stat().st_size,
                "created_at": datetime.fromtimestamp(report_file.stat().st_mtime).isoformat(),
                "download_url": f"/reports/download/{report_file.name}",
            })

    return sorted(reports, key=lambda r: r["created_at"], reverse=True)


@router.get("/download/{filename}")
async def download_report(filename: str) -> FileResponse:
    """Download a generated report."""
    # Sanitize filename
    if "/" in filename or ".." in filename:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid filename"
        )

    report_path = RESULTS_DIR / filename
    if not report_path.exists():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=f"Report not found: {filename}"
        )

    # Determine media type
    if filename.endswith(".html"):
        media_type = "text/html"
    elif filename.endswith(".json"):
        media_type = "application/json"
    elif filename.endswith(".csv"):
        media_type = "text/csv"
    else:
        media_type = "application/octet-stream"

    return FileResponse(
        path=report_path,
        filename=filename,
        media_type=media_type,
    )
