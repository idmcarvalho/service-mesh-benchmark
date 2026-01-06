# Service Mesh Benchmark - Quick Start Guide

Get up and running with the Service Mesh Benchmark platform in under 5 minutes!

## Prerequisites

- **Docker & Docker Compose**: For running the API and frontend
- **Kubernetes Cluster**: With `kubectl` configured (minikube, kind, or cloud cluster)
- **Basic Tools**: curl, git

Optional (for running benchmarks):
- `wrk` - HTTP load testing
- `ghz` - gRPC benchmarking
- `websocat` or `wscat` - WebSocket testing

## Quick Start (Simple Mode)

### 1. Clone and Start

```bash
# Clone the repository
git clone <repository-url>
cd service-mesh-benchmark

# Start the services (API + Frontend)
docker-compose up -d

# Check the logs
docker-compose logs -f api
```

The API will be available at:
- **API**: http://localhost:8000
- **API Docs**: http://localhost:8000/docs
- **Frontend**: http://localhost:3000

### 2. Verify Installation

```bash
# Check API health
curl http://localhost:8000/health

# Expected response:
# {"status":"healthy","version":"1.0.0"}
```

### 3. Deploy a Test Service

For this example, we'll deploy a simple HTTP service to benchmark:

```bash
# Create a test namespace
kubectl create namespace benchmark-test

# Deploy a simple nginx service
kubectl create deployment nginx --image=nginx:latest -n benchmark-test
kubectl expose deployment nginx --port=80 --target-port=80 -n benchmark-test

# Verify the service is running
kubectl get pods -n benchmark-test
```

### 4. Run Your First Benchmark

```bash
# Run an HTTP benchmark (baseline - no service mesh)
curl -X POST http://localhost:8000/benchmarks/start \
  -H "Content-Type: application/json" \
  -d '{
    "test_type": "http",
    "mesh_type": "baseline",
    "namespace": "benchmark-test",
    "duration": 60,
    "concurrent_connections": 100,
    "service_url": "http://nginx.benchmark-test.svc.cluster.local"
  }'

# Expected response:
# {
#   "job_id": "http_baseline_20260105_120000",
#   "status": "pending",
#   "message": "Benchmark http started",
#   "started_at": "2026-01-05T12:00:00Z"
# }
```

### 5. Check Benchmark Status

```bash
# List all jobs
curl http://localhost:8000/benchmarks/jobs

# Check specific job status (use your job_id from step 4)
curl http://localhost:8000/benchmarks/jobs/http_baseline_20260105_120000

# Get results (once status is "completed")
curl http://localhost:8000/benchmarks/jobs/http_baseline_20260105_120000/result
```

### 6. View Results

```bash
# Get metrics summary
curl http://localhost:8000/metrics/summary

# List all result files
curl http://localhost:8000/metrics/results
```

Or open the web dashboard:
```
http://localhost:3000
```

## Using the API Docs

The interactive API documentation is available at http://localhost:8000/docs

You can:
1. Browse all available endpoints
2. Try API calls directly from the browser
3. View request/response schemas
4. Download OpenAPI specification

## Common Benchmarks

### HTTP Load Test

```bash
curl -X POST http://localhost:8000/benchmarks/start \
  -H "Content-Type: application/json" \
  -d '{
    "test_type": "http",
    "mesh_type": "baseline",
    "namespace": "default",
    "duration": 120,
    "concurrent_connections": 200,
    "service_url": "http://my-service.default.svc.cluster.local"
  }'
```

### gRPC Benchmark

```bash
curl -X POST http://localhost:8000/benchmarks/start \
  -H "Content-Type: application/json" \
  -d '{
    "test_type": "grpc",
    "mesh_type": "baseline",
    "namespace": "default",
    "duration": 120,
    "concurrent_connections": 100,
    "service_url": "my-grpc-service.default.svc.cluster.local:9000"
  }'
```

### WebSocket Test

```bash
curl -X POST http://localhost:8000/benchmarks/start \
  -H "Content-Type": "application/json" \
  -d '{
    "test_type": "websocket",
    "mesh_type": "baseline",
    "namespace": "default",
    "duration": 60,
    "concurrent_connections": 50,
    "service_url": "ws://my-ws-service.default.svc.cluster.local/ws"
  }'
```

### ML Inference Benchmark

```bash
curl -X POST http://localhost:8000/benchmarks/start \
  -H "Content-Type": "application/json" \
  -d '{
    "test_type": "ml",
    "mesh_type": "baseline",
    "namespace": "default",
    "duration": 120,
    "concurrent_connections": 10,
    "service_url": "http://ml-service.default.svc.cluster.local:8080/predict"
  }'
```

## Testing with Service Meshes

### 1. Install a Service Mesh

```bash
# Example: Install Istio
istioctl install --set profile=demo -y

# Label namespace for sidecar injection
kubectl label namespace benchmark-test istio-injection=enabled
```

### 2. Deploy Workloads with Mesh

```bash
# Restart pods to inject sidecars
kubectl rollout restart deployment/nginx -n benchmark-test

# Verify sidecars are injected
kubectl get pods -n benchmark-test
# Should show 2/2 containers (app + sidecar)
```

### 3. Run Benchmark with Mesh

```bash
curl -X POST http://localhost:8000/benchmarks/start \
  -H "Content-Type: application/json" \
  -d '{
    "test_type": "http",
    "mesh_type": "istio",
    "namespace": "benchmark-test",
    "duration": 60,
    "concurrent_connections": 100,
    "service_url": "http://nginx.benchmark-test.svc.cluster.local"
  }'
```

### 4. Compare Results

```bash
# Get comparison between baseline and mesh
curl http://localhost:8000/metrics/summary
```

## Configuration

### Environment Variables

Create a `.env` file to customize settings:

```bash
# API Configuration
DEBUG=false
API_HOST=0.0.0.0
API_PORT=8000
LOG_LEVEL=INFO

# CORS (if using custom frontend)
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080

# Optional: Enable JSON persistence (default: enabled)
PERSISTENCE_ENABLED=true

# Optional: Enable database (requires PostgreSQL)
# DATABASE_ENABLED=true
# DATABASE_URL=postgresql://user:pass@localhost:5432/dbname

# Optional: Enable Redis (requires Redis server)
# REDIS_ENABLED=true
# REDIS_URL=redis://localhost:6379/0
```

## Data Persistence

By default, the benchmark uses:
- **In-memory job tracking** - Fast, no database required
- **JSON file persistence** - Job history saved to `workloads/scripts/results/jobs_history.json`
- **Result files** - Stored in `workloads/scripts/results/`

### Viewing Persisted Data

```bash
# View all results
ls -lh workloads/scripts/results/

# View job history
cat workloads/scripts/results/jobs_history.json | jq '.'

# View specific result
cat workloads/scripts/results/baseline_http_*.json | jq '.'
```

## Stopping and Cleaning Up

```bash
# Stop services
docker-compose down

# Remove volumes (caution: deletes all data)
docker-compose down -v

# Clean up Kubernetes resources
kubectl delete namespace benchmark-test
```

## Troubleshooting

### API Won't Start

```bash
# Check logs
docker-compose logs api

# Common issues:
# 1. Port 8000 already in use - change API_PORT in .env
# 2. Kubernetes config not found - ensure ~/.kube/config exists
```

### Benchmark Fails

```bash
# Check if service is accessible from within cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://your-service.namespace.svc.cluster.local

# Check benchmark tool is installed
docker-compose exec api which wrk
docker-compose exec api which ghz
```

### No Results Generated

```bash
# Check results directory
docker-compose exec api ls -la /app/workloads/scripts/results

# Check script permissions
docker-compose exec api ls -la /app/workloads/scripts/runners
```

## Next Steps

1. **Install Service Meshes**: Try Istio, Cilium, Linkerd, or Consul
2. **Run Comparative Tests**: Benchmark the same workload across different meshes
3. **Generate Reports**: Use the `/reports/generate` endpoint to create HTML/CSV reports
4. **Explore eBPF Probes**: For kernel-level latency measurement
5. **Deploy to Production**: Use `docker-compose -f docker-compose.full.yml up` for the full stack

## Additional Resources

- **Full README**: See [README.md](README.md) for complete documentation
- **API Reference**: http://localhost:8000/docs
- **Testing Guide**: See [docs/testing/TESTING.md](docs/testing/TESTING.md)
- **Deployment Guide**: See [DEPLOYMENT.md](DEPLOYMENT.md)

## Support

If you encounter issues:
1. Check the logs: `docker-compose logs`
2. Verify Kubernetes access: `kubectl cluster-info`
3. Review the [troubleshooting section](#troubleshooting)
4. Open an issue on GitHub with logs and error messages

---

**You're ready to benchmark!** Start comparing service mesh performance and find the best fit for your workloads.
