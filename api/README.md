# Service Mesh Benchmark API

Comprehensive REST API for orchestrating service mesh benchmarks, collecting metrics, and generating reports.

## Overview

This API provides unified access to all service mesh benchmarking capabilities:

- **HTTP Load Testing** - wrk-based HTTP benchmark execution
- **gRPC Testing** - ghz-based gRPC benchmark execution
- **WebSocket Testing** - WebSocket load testing
- **ML Workload Testing** - Machine learning inference workload testing
- **eBPF Probes** - Low-level latency measurement using eBPF
- **Metrics Collection** - Centralized metrics storage and retrieval
- **Report Generation** - HTML, JSON, and CSV report generation
- **Kubernetes Integration** - Direct cluster inspection and status

## Architecture

```
api/
├── main.py              # FastAPI application entry point
├── config.py            # Configuration and global settings
├── models.py            # Pydantic request/response models
├── state.py             # Shared application state
├── endpoints/           # Organized endpoint modules
│   ├── health.py        # Health and status endpoints
│   ├── benchmarks.py    # Benchmark execution
│   ├── ebpf.py          # eBPF probe control
│   ├── metrics.py       # Metrics and results
│   ├── reports.py       # Report generation
│   └── kubernetes.py    # Kubernetes integration
└── README.md            # This file
```

## Quick Start

### Installation

```bash
# Install dependencies
pip install -e .

# Or install from requirements.txt
pip install -r tests/requirements.txt
```

### Running the API

```bash
# Development mode with auto-reload
python -m api.main

# Or using uvicorn directly
uvicorn api.main:app --reload --host 0.0.0.0 --port 8000
```

### Access Documentation

Once running, visit:
- **Swagger UI**: http://localhost:8000/docs
- **ReDoc**: http://localhost:8000/redoc

## API Endpoints

### Health & Status

#### `GET /health`
Health check endpoint.

**Response:**
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "timestamp": "2025-10-26T10:30:00Z",
  "kubernetes_connected": true,
  "active_jobs": 2
}
```

#### `GET /status`
Detailed system status including available benchmarks and running jobs.

**Response:**
```json
{
  "timestamp": "2025-10-26T10:30:00Z",
  "kubernetes": {
    "connected": true,
    "version": "1.28"
  },
  "benchmarks": {
    "available": ["http-load-test", "grpc-test", "websocket-test", "ml-workload"],
    "scripts_dir": "/path/to/benchmarks/scripts"
  },
  "ebpf": {
    "available": true,
    "probe_path": "/path/to/latency-probe"
  },
  "jobs": {
    "total": 5,
    "running": 2,
    "completed": 3,
    "failed": 0
  }
}
```

### Benchmarks

#### `POST /benchmarks/start`
Start a new benchmark test.

**Request Body:**
```json
{
  "test_type": "http",
  "mesh_type": "istio",
  "namespace": "benchmark",
  "duration": 60,
  "concurrent_connections": 100,
  "service_url": "http-server.benchmark.svc.cluster.local"
}
```

**Parameters:**
- `test_type`: `http`, `grpc`, `websocket`, or `ml`
- `mesh_type`: `baseline`, `istio`, `cilium`, `linkerd`, or `consul`
- `namespace`: Kubernetes namespace
- `duration`: Test duration in seconds (10-3600)
- `concurrent_connections`: Number of concurrent connections (1-10000)
- `service_url`: (Optional) Override default service URL

**Response:**
```json
{
  "job_id": "http_istio_20251026_103000",
  "status": "pending",
  "message": "Benchmark http started",
  "started_at": "2025-10-26T10:30:00Z"
}
```

#### `GET /benchmarks/jobs`
List all benchmark jobs.

**Query Parameters:**
- `status_filter`: Filter by status (`pending`, `running`, `completed`, `failed`)
- `test_type_filter`: Filter by test type

**Response:**
```json
[
  {
    "job_id": "http_istio_20251026_103000",
    "status": "completed",
    "test_type": "http",
    "mesh_type": "istio",
    "started_at": "2025-10-26T10:30:00Z",
    "completed_at": "2025-10-26T10:31:30Z",
    "result_file": "/path/to/result.json",
    "error": null
  }
]
```

#### `GET /benchmarks/jobs/{job_id}`
Get status of a specific job.

#### `GET /benchmarks/jobs/{job_id}/result`
Get the result data of a completed job.

#### `DELETE /benchmarks/jobs/{job_id}`
Cancel or remove a job.

### eBPF Probes

#### `POST /ebpf/probe/start`
Start eBPF latency probe.

**Request Body:**
```json
{
  "duration": 60,
  "namespace": "default",
  "pod_filter": "app=http-server",
  "output_format": "json"
}
```

**Response:**
```json
{
  "job_id": "ebpf_probe_20251026_103000",
  "status": "pending",
  "message": "eBPF probe started",
  "started_at": "2025-10-26T10:30:00Z"
}
```

#### `GET /ebpf/probe/status`
Check eBPF probe availability and status.

**Response:**
```json
{
  "available": true,
  "probe_path": "/path/to/latency-probe",
  "running_probes": 1,
  "build_instructions": null
}
```

### Metrics & Results

#### `GET /metrics/results`
List available benchmark results.

**Query Parameters:**
- `mesh_type`: Filter by mesh type
- `test_type`: Filter by test type
- `limit`: Maximum results to return (1-500, default 50)

**Response:**
```json
[
  {
    "file": "http_test_20251026_103000.json",
    "test_type": "http",
    "mesh_type": "istio",
    "timestamp": "20251026_103000",
    "metrics": {
      "requests_per_sec": 1234.56,
      "avg_latency_ms": 12.34
    }
  }
]
```

#### `GET /metrics/results/{filename}`
Get a specific result file.

#### `GET /metrics/summary`
Get aggregated metrics summary.

**Response:**
```json
{
  "total_tests": 15,
  "by_mesh_type": {
    "baseline": 5,
    "istio": 5,
    "cilium": 5
  },
  "by_test_type": {
    "http": 10,
    "grpc": 5
  },
  "results_dir": "/path/to/results"
}
```

### Reports

#### `POST /reports/generate`
Generate a benchmark report.

**Request Body:**
```json
{
  "format": "html",
  "filter_mesh_type": "istio",
  "filter_test_type": "http"
}
```

**Parameters:**
- `format`: `html`, `json`, or `csv`
- `filter_mesh_type`: (Optional) Filter by mesh type
- `filter_test_type`: (Optional) Filter by test type

**Response:**
```json
{
  "status": "completed",
  "report_file": "report_20251026_103000.html",
  "format": "html",
  "download_url": "/reports/download/report_20251026_103000.html"
}
```

#### `GET /reports/list`
List all generated reports.

#### `GET /reports/download/{filename}`
Download a specific report file.

### Kubernetes Integration

#### `GET /kubernetes/namespaces`
List all Kubernetes namespaces.

**Response:**
```json
["default", "kube-system", "istio-system", "benchmark"]
```

#### `GET /kubernetes/services/{namespace}`
List services in a namespace.

**Response:**
```json
[
  {
    "name": "http-server",
    "type": "ClusterIP",
    "cluster_ip": "10.96.1.100",
    "ports": [
      {"port": 80, "protocol": "TCP", "name": "http"}
    ]
  }
]
```

#### `GET /kubernetes/pods/{namespace}`
List pods in a namespace.

**Query Parameters:**
- `label_selector`: Filter pods by label selector

**Response:**
```json
[
  {
    "name": "http-server-abc123",
    "status": "Running",
    "node": "node-1",
    "ip": "10.244.1.5",
    "ready": true,
    "containers": ["http-server", "istio-proxy"]
  }
]
```

#### `GET /kubernetes/mesh-status/{namespace}`
Get service mesh installation status.

**Query Parameters:**
- `mesh_type`: Service mesh type to check

**Response:**
```json
{
  "mesh_type": "istio",
  "namespace": "istio-system",
  "installed": true,
  "components": ["istiod", "istio-ingressgateway"],
  "healthy": true
}
```

#### `GET /kubernetes/nodes`
List cluster nodes with details.

## Usage Examples

### Example 1: Run HTTP Benchmark

```python
import httpx

# Start benchmark
response = httpx.post("http://localhost:8000/benchmarks/start", json={
    "test_type": "http",
    "mesh_type": "istio",
    "namespace": "benchmark",
    "duration": 60,
    "concurrent_connections": 100
})
job = response.json()
job_id = job["job_id"]

# Check status
status = httpx.get(f"http://localhost:8000/benchmarks/jobs/{job_id}").json()
print(f"Status: {status['status']}")

# Get results when complete
if status["status"] == "completed":
    results = httpx.get(f"http://localhost:8000/benchmarks/jobs/{job_id}/result").json()
    print(f"RPS: {results['metrics']['requests_per_sec']}")
```

### Example 2: Start eBPF Probe

```python
import httpx

# Start probe
response = httpx.post("http://localhost:8000/ebpf/probe/start", json={
    "duration": 30,
    "namespace": "default",
    "pod_filter": "app=my-app",
    "output_format": "json"
})
probe_job = response.json()
print(f"Probe started: {probe_job['job_id']}")
```

### Example 3: Generate Report

```python
import httpx

# Generate HTML report
response = httpx.post("http://localhost:8000/reports/generate", json={
    "format": "html",
    "filter_mesh_type": "istio"
})
report = response.json()

# Download report
report_url = f"http://localhost:8000{report['download_url']}"
print(f"Download report: {report_url}")
```

### Example 4: Using `curl`

```bash
# Health check
curl http://localhost:8000/health

# Start HTTP benchmark
curl -X POST http://localhost:8000/benchmarks/start \
  -H "Content-Type: application/json" \
  -d '{
    "test_type": "http",
    "mesh_type": "baseline",
    "namespace": "default",
    "duration": 60
  }'

# List jobs
curl http://localhost:8000/benchmarks/jobs

# Get job status
curl http://localhost:8000/benchmarks/jobs/http_baseline_20251026_103000

# List Kubernetes namespaces
curl http://localhost:8000/kubernetes/namespaces
```

## Configuration

### Environment Variables

The API can be configured using environment variables:

- `KUBECONFIG`: Path to kubeconfig file (default: `~/.kube/config`)
- `API_HOST`: API host (default: `0.0.0.0`)
- `API_PORT`: API port (default: `8000`)

### Project Structure

The API expects the following project structure:

```
service-mesh-benchmark/
├── api/                      # API package
├── benchmarks/
│   ├── scripts/              # Benchmark scripts
│   └── results/              # Results directory
├── ebpf-probes/
│   └── latency-probe/        # eBPF probe
├── tests/                    # Test models
└── generate-report.py        # Report generator
```

## Development

### Adding New Endpoints

1. Create a new router in `api/endpoints/`:

```python
from fastapi import APIRouter

router = APIRouter(prefix="/my-feature", tags=["MyFeature"])

@router.get("/endpoint")
async def my_endpoint():
    return {"message": "Hello"}
```

2. Import and register in `api/main.py`:

```python
from api.endpoints import my_feature

app.include_router(my_feature.router)
```

### Testing

```bash
# Install dev dependencies
pip install -e ".[dev]"

# Run tests
pytest tests/

# Run with coverage
pytest --cov=api tests/
```

## Deployment

### Docker

Create a `Dockerfile`:

```dockerfile
FROM python:3.11-slim

WORKDIR /app
COPY . /app

RUN pip install -e .

EXPOSE 8000
CMD ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

Build and run:

```bash
docker build -t service-mesh-benchmark-api .
docker run -p 8000:8000 -v ~/.kube/config:/root/.kube/config service-mesh-benchmark-api
```

### Kubernetes

Create a deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: benchmark-api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: benchmark-api
  template:
    metadata:
      labels:
        app: benchmark-api
    spec:
      containers:
      - name: api
        image: service-mesh-benchmark-api:latest
        ports:
        - containerPort: 8000
---
apiVersion: v1
kind: Service
metadata:
  name: benchmark-api
spec:
  selector:
    app: benchmark-api
  ports:
  - port: 80
    targetPort: 8000
```

## Troubleshooting

### Kubernetes Not Connected

If you see "kubernetes_connected": false:

1. Check kubeconfig: `kubectl cluster-info`
2. Verify KUBECONFIG environment variable
3. Ensure cluster is accessible from API host

### eBPF Probe Not Available

If eBPF endpoints return 503:

1. Build the probe: `cd ebpf-probes/latency-probe && ./build.sh`
2. Verify probe exists: `ls ebpf-probes/latency-probe/latency-probe-userspace/target/release/latency-probe`
3. Check eBPF requirements: See [ebpf-probes/SETUP.md](../ebpf-probes/SETUP.md)

### Benchmark Scripts Not Found

Ensure benchmark scripts exist:

```bash
ls benchmarks/scripts/
# Should show: http-load-test.sh, grpc-test.sh, websocket-test.sh, ml-workload.sh
```


## Security Considerations

- **Authentication**: Consider adding authentication middleware for production
- **CORS**: Configure CORS appropriately for your environment
- **Rate Limiting**: Add rate limiting for production deployments
- **Input Validation**: All inputs are validated using Pydantic models
- **File Access**: Filenames are sanitized to prevent directory traversal

