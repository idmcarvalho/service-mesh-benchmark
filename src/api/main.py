"""Service Mesh Benchmark API - Main Application.

FastAPI application to orchestrate benchmarks, collect metrics, and generate reports.
This API doesn't handle gRPC/WebSocket directly - it orchestrates the benchmark scripts
that use appropriate tools (ghz for gRPC, wrk for HTTP, etc.).
"""

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from kubernetes import config as k8s_config
from starlette.middleware.base import BaseHTTPMiddleware

from src.api.config import RESULTS_DIR
from src.api.settings import settings

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
# Security Headers Middleware
# ============================================================================


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Add security headers to all responses."""

    async def dispatch(self, request: Request, call_next):
        """Process request and add security headers to response."""
        response = await call_next(request)

        if settings.security_headers_enabled:
            # Prevent clickjacking
            response.headers["X-Frame-Options"] = "DENY"

            # Prevent MIME type sniffing
            response.headers["X-Content-Type-Options"] = "nosniff"

            # Enable XSS protection
            response.headers["X-XSS-Protection"] = "1; mode=block"

            # Referrer policy
            response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"

            # Content Security Policy
            response.headers["Content-Security-Policy"] = (
                "default-src 'self'; "
                "script-src 'self' 'unsafe-inline' 'unsafe-eval'; "
                "style-src 'self' 'unsafe-inline'; "
                "img-src 'self' data: https:; "
                "font-src 'self' data:; "
                "connect-src 'self'"
            )

            # Permissions policy
            response.headers["Permissions-Policy"] = (
                "geolocation=(), microphone=(), camera=(), payment=()"
            )

        return response


# ============================================================================
# Configure CORS Middleware
# ============================================================================
# Production-ready CORS configuration
# CORS origins are loaded from settings (environment variables)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization", "X-Requested-With"],
    max_age=3600,  # Cache preflight requests for 1 hour
)

# Add security headers middleware
app.add_middleware(SecurityHeadersMiddleware)

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
    # Print configuration info
    print("=" * 60)
    print("Service Mesh Benchmark API")
    print("=" * 60)
    print(f"Environment: {'Production' if settings.is_production else 'Development'}")
    print(f"Debug mode: {settings.debug}")
    print(f"API Host: {settings.api_host}:{settings.api_port}")
    print(f"CORS Origins: {settings.cors_origins}")
    print(f"Security Headers: {'Enabled' if settings.security_headers_enabled else 'Disabled'}")
    print(f"Log Level: {settings.log_level}")

    # Validate production configuration
    warnings = settings.validate_production_config()
    if warnings:
        print("\n" + "!" * 60)
        print("SECURITY WARNINGS:")
        for warning in warnings:
            print(f"  ⚠️  {warning}")
        print("!" * 60 + "\n")

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
    print(f"  Docs: http://{settings.api_host}:{settings.api_port}/docs")
    print(f"  ReDoc: http://{settings.api_host}:{settings.api_port}/redoc")
    print("=" * 60)


@app.on_event("shutdown")
async def shutdown_event() -> None:
    """Clean up on shutdown."""
    print("Shutting down Service Mesh Benchmark API...")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "src.api.main:app",
        host=settings.api_host,
        port=settings.api_port,
        reload=settings.debug,
        log_level=settings.log_level.lower(),
    )
