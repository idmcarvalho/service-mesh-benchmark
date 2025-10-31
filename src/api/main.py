"""Service Mesh Benchmark API - Main Application.

FastAPI application to orchestrate benchmarks, collect metrics, and generate reports.
This API doesn't handle gRPC/WebSocket directly - it orchestrates the benchmark scripts
that use appropriate tools (ghz for gRPC, wrk for HTTP, etc.).
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from kubernetes import config as k8s_config

from src.api.config import RESULTS_DIR

# Import all endpoint routers
from src.api.endpoints import (
    benchmarks,
    ebpf,
    health,
    kubernetes,
    metrics,
    reports,
)

# Initialize FastAPI app
app = FastAPI(
    title="Service Mesh Benchmark API",
    description=(
        "API for orchestrating service mesh benchmarks, metrics collection, "
        "and report generation. Supports HTTP, gRPC, WebSocket, and ML workload benchmarks, "
        "along with eBPF-based latency probes."
    ),
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_tags=[
        {
            "name": "Health",
            "description": "Health check and system status endpoints",
        },
        {
            "name": "Benchmarks",
            "description": "Benchmark execution and management (HTTP, gRPC, WebSocket, ML)",
        },
        {
            "name": "eBPF",
            "description": "eBPF probe control for low-level latency measurement",
        },
        {
            "name": "Metrics",
            "description": "Metrics collection and results retrieval",
        },
        {
            "name": "Reports",
            "description": "Report generation and download",
        },
        {
            "name": "Kubernetes",
            "description": "Kubernetes cluster integration and status",
        },
    ],
)

# ============================================================================
# Configure CORS Middleware
# ============================================================================
# Production-ready CORS configuration
# Set ALLOWED_ORIGINS environment variable for production
import os

ALLOWED_ORIGINS = os.getenv(
    "ALLOWED_ORIGINS",
    "http://localhost:3000,http://localhost:8000,http://localhost:8080"
).split(",")

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization", "X-Requested-With"],
    max_age=3600,  # Cache preflight requests for 1 hour
)

# ============================================================================
# Register All API Routers
# ============================================================================
# Health and status
app.include_router(health.router)

# Benchmark execution
app.include_router(benchmarks.router)

# eBPF probes
app.include_router(ebpf.router)

# Metrics and results
app.include_router(metrics.router)

# Report generation
app.include_router(reports.router)

# Kubernetes integration
app.include_router(kubernetes.router)


# ============================================================================
# Application Lifecycle Events
# ============================================================================


@app.on_event("startup")
async def startup_event() -> None:
    """Initialize the application on startup."""
    # Ensure results directory exists
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    print(f"✓ Results directory: {RESULTS_DIR}")

    # Try to load Kubernetes config
    try:
        k8s_config.load_kube_config()
        print("✓ Kubernetes configuration loaded")
    except Exception as e:
        print(f"⚠ Kubernetes configuration not loaded: {e}")

    print("✓ Service Mesh Benchmark API started")
    print(f"  Docs: http://localhost:8000/docs")
    print(f"  ReDoc: http://localhost:8000/redoc")


@app.on_event("shutdown")
async def shutdown_event() -> None:
    """Clean up on shutdown."""
    print("Shutting down Service Mesh Benchmark API...")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "src.api.main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info",
    )
