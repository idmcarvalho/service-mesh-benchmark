# Service Mesh Benchmark - Deployment & Integration Guide

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Svelte Frontend Dashboard                     │
│              Real-time Metrics & Benchmark Results               │
└────────────────────────────┬────────────────────────────────────┘
                             │ HTTP REST API + WebSocket
┌────────────────────────────┴────────────────────────────────────┐
│                        FastAPI Backend                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ Benchmarks   │  │   eBPF       │  │  Kubernetes  │         │
│  │  Endpoints   │  │  Endpoints   │  │  Integration │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
└────────────┬───────────────┬───────────────┬───────────────────┘
             │               │               │
    ┌────────┴────────┐ ┌───┴────┐   ┌─────┴────────┐
    │   PostgreSQL    │ │ Redis  │   │  Kubernetes  │
    │    Database     │ │ Queue  │   │    Cluster   │
    └─────────────────┘ └────────┘   └──────────────┘
             │                              │
    ┌────────┴────────┐            ┌───────┴────────┐
    │ Benchmark Jobs  │            │ eBPF Probes    │
    │  - HTTP Tests   │            │ Service Meshes │
    │  - gRPC Tests   │            │  - Istio       │
    │  - WebSocket    │            │  - Cilium      │
    │  - ML Workloads │            │  - Linkerd     │
    └─────────────────┘            └────────────────┘
```

## Prerequisites

### System Requirements
- **OS**: Linux (Ubuntu 20.04+ recommended) or macOS
- **CPU**: 4+ cores
- **RAM**: 8GB minimum, 16GB recommended
- **Disk**: 50GB+ free space
- **Kernel**: Linux 5.8+ (for eBPF support)

### Required Software
1. **Docker & Docker Compose**
   ```bash
   curl -fsSL https://get.docker.com | sh
   sudo apt-get install docker-compose-plugin
   ```

2. **Python 3.11+**
   ```bash
   sudo apt-get install python3.11 python3.11-venv python3-pip
   ```

3. **Rust (for eBPF probes)**
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   rustup target add bpfel-unknown-none
   ```

4. **Node.js 18+ (for Svelte frontend)**
   ```bash
   curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
   sudo apt-get install -y nodejs
   ```

5. **Kubernetes CLI & Cluster Access**
   ```bash
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
   ```

6. **Benchmark Tools**
   ```bash
   sudo apt-get install wrk
   go install github.com/bojand/ghz/cmd/ghz@latest
   go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest
   ```

---

## Quick Start (Development)

### 1. Clone and Setup Backend

```bash
git clone <repo-url>
cd service-mesh-benchmark

# Create virtual environment
python3.11 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r src/api/requirements.txt
```

### 2. Configure Environment

```bash
cp .env.example .env
nano .env
```

**Key Configuration:**
```env
DATABASE_URL=postgresql://benchmark:benchmark@localhost:5432/service_mesh_benchmark
DEBUG=true
API_HOST=0.0.0.0
API_PORT=8000
ALLOWED_ORIGINS=http://localhost:5173,http://localhost:3000
```

### 3. Start Infrastructure

```bash
# Start services
docker-compose up -d postgres redis

# Initialize database
python src/api/init_db.py
```

### 4. Build eBPF Probes

```bash
cd src/probes/latency
./build.sh
# Verify: ls -la daemon/target/release/latency-probe
```

### 5. Start Backend API

```bash
python -m uvicorn src.api.main:app --reload --host 0.0.0.0 --port 8000
```

API available at:
- **Docs**: http://localhost:8000/docs
- **Health**: http://localhost:8000/health

---

## Svelte Frontend Setup

### 1. Initialize Svelte Project

```bash
mkdir frontend
cd frontend

# Create SvelteKit project
npm create svelte@latest .
# Choose: Skeleton project, TypeScript, ESLint, Prettier

npm install
```

### 2. Install Dependencies

```bash
# Core dependencies
npm install axios @tanstack/svelte-query

# UI components & charts
npm install chart.js svelte-chartjs
npm install lucide-svelte  # Icons
npm install tailwindcss postcss autoprefixer
npx tailwindcss init -p

# Real-time updates
npm install socket.io-client
```

### 3. Configure API Client

Create `frontend/src/lib/api.ts`:
```typescript
import axios from 'axios';

const API_BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000';

export const api = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

// API endpoints
export const benchmarkAPI = {
  start: (data: BenchmarkRequest) => api.post('/benchmarks/start', data),
  listJobs: (filters?: JobFilters) => api.get('/benchmarks/jobs', { params: filters }),
  getJob: (jobId: string) => api.get(`/benchmarks/jobs/${jobId}`),
  getResult: (jobId: string) => api.get(`/benchmarks/jobs/${jobId}/result`),
  cancel: (jobId: string) => api.delete(`/benchmarks/jobs/${jobId}`),
};

export const metricsAPI = {
  results: (filters?: MetricFilters) => api.get('/metrics/results', { params: filters }),
  summary: (meshType?: string) => api.get('/metrics/summary', { params: { mesh_type: meshType } }),
};

export const ebpfAPI = {
  start: (data: ProbeRequest) => api.post('/ebpf/probe/start', data),
  status: () => api.get('/ebpf/probe/status'),
};

export const kubernetesAPI = {
  namespaces: () => api.get('/kubernetes/namespaces'),
  services: (namespace: string) => api.get(`/kubernetes/services/${namespace}`),
  pods: (namespace: string) => api.get(`/kubernetes/pods/${namespace}`),
  meshStatus: (namespace: string, meshType: string) =>
    api.get(`/kubernetes/mesh-status/${namespace}`, { params: { mesh_type: meshType } }),
};
```

### 4. Sample Svelte Component

Create `frontend/src/routes/+page.svelte`:
```svelte
<script lang="ts">
  import { onMount } from 'svelte';
  import { benchmarkAPI } from '$lib/api';
  import type { BenchmarkJob } from '$lib/types';

  let jobs: BenchmarkJob[] = [];
  let loading = true;

  onMount(async () => {
    await loadJobs();
    // Auto-refresh every 5 seconds
    const interval = setInterval(loadJobs, 5000);
    return () => clearInterval(interval);
  });

  async function loadJobs() {
    try {
      const response = await benchmarkAPI.listJobs();
      jobs = response.data;
    } catch (error) {
      console.error('Failed to load jobs:', error);
    } finally {
      loading = false;
    }
  }

  async function startBenchmark() {
    try {
      await benchmarkAPI.start({
        test_type: 'http',
        mesh_type: 'baseline',
        namespace: 'default',
        duration: 60,
        concurrent_connections: 100
      });
      await loadJobs();
    } catch (error) {
      console.error('Failed to start benchmark:', error);
    }
  }
</script>

<div class="container">
  <h1>Service Mesh Benchmark Dashboard</h1>

  <button on:click={startBenchmark}>Start Benchmark</button>

  {#if loading}
    <p>Loading...</p>
  {:else if jobs.length === 0}
    <p>No benchmark jobs found.</p>
  {:else}
    <table>
      <thead>
        <tr>
          <th>Job ID</th>
          <th>Type</th>
          <th>Mesh</th>
          <th>Status</th>
          <th>Started</th>
        </tr>
      </thead>
      <tbody>
        {#each jobs as job}
          <tr>
            <td>{job.job_id}</td>
            <td>{job.test_type}</td>
            <td>{job.mesh_type}</td>
            <td class="status-{job.status}">{job.status}</td>
            <td>{new Date(job.started_at).toLocaleString()}</td>
          </tr>
        {/each}
      </tbody>
    </table>
  {/if}
</div>

<style>
  .status-pending { color: orange; }
  .status-running { color: blue; }
  .status-completed { color: green; }
  .status-failed { color: red; }
</style>
```

### 5. Start Frontend Development Server

```bash
cd frontend
npm run dev -- --open
```

Svelte app runs on: http://localhost:5173

---

## Production Deployment

### Full Stack with Docker Compose

Update `docker-compose.yml` to include frontend:

```yaml
  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
    container_name: benchmark-frontend
    ports:
      - "3000:3000"
    environment:
      VITE_API_URL: http://api:8000
    depends_on:
      - api
    networks:
      - benchmark-network
```

Create `frontend/Dockerfile`:
```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/build ./build
COPY package*.json ./
RUN npm ci --production
EXPOSE 3000
CMD ["node", "build"]
```

Deploy everything:
```bash
docker-compose up -d --build
```

---

## Integration Components

### 1. PostgreSQL Database

**Initialize:**
```bash
python src/api/init_db.py
```

**Tables:**
- `benchmark_jobs` - Benchmark executions
- `ebpf_probe_jobs` - eBPF probe runs
- `reports` - Generated reports

### 2. Benchmark Scripts

**Location**: `benchmarks/scripts/`

**Integration Flow:**
1. Frontend → API request
2. API → Creates database record
3. API → Spawns background task
4. Task → Executes benchmark script
5. Script → Writes results to `RESULTS_DIR`
6. API → Updates database
7. Frontend → Polls for results

### 3. eBPF Probes

**Build:**
```bash
cd src/probes/latency && ./build.sh
```

**Run:**
```bash
# Via API
curl -X POST http://localhost:8000/ebpf/probe/start \
  -d '{"duration": 60, "output_format": "json"}'

# Direct
sudo ./src/probes/latency/daemon/target/release/latency-probe --duration 60
```

**Requirements:**
- Linux kernel 5.8+
- `CAP_SYS_ADMIN` and `CAP_NET_ADMIN` capabilities
- Root or privileged container

### 4. Kubernetes Integration

**Access Required:**
```bash
export KUBECONFIG=/path/to/kubeconfig
```

**Capabilities:**
- List namespaces, pods, services
- Detect service mesh installations
- Monitor resource usage
- Deploy benchmark workloads

---

## Svelte Frontend Features

### Recommended Pages

1. **Dashboard** (`/`)
   - Active jobs overview
   - System health status
   - Quick stats

2. **Benchmarks** (`/benchmarks`)
   - Start new benchmark
   - View job history
   - Real-time progress
   - Results visualization

3. **Metrics** (`/metrics`)
   - Latency charts
   - Throughput graphs
   - Comparison views
   - Export data

4. **eBPF Probes** (`/probes`)
   - Start probe
   - View results
   - Connection metrics
   - Histogram visualization

5. **Reports** (`/reports`)
   - Generate reports
   - Download results
   - Share links

### Recommended Libraries

```json
{
  "dependencies": {
    "@sveltejs/kit": "^2.0.0",
    "axios": "^1.6.0",
    "@tanstack/svelte-query": "^5.0.0",
    "chart.js": "^4.4.0",
    "svelte-chartjs": "^3.1.0",
    "lucide-svelte": "^0.300.0",
    "tailwindcss": "^3.4.0",
    "socket.io-client": "^4.6.0"
  }
}
```

### Real-time Updates with WebSocket

```typescript
// src/lib/websocket.ts
import { io } from 'socket.io-client';

const socket = io('http://localhost:8000');

export function subscribeToJob(jobId: string, callback: (data: any) => void) {
  socket.on(`job:${jobId}`, callback);
  return () => socket.off(`job:${jobId}`, callback);
}
```

---

## Testing the Integration

### 1. Health Check
```bash
curl http://localhost:8000/health
```

### 2. Start Benchmark via API
```bash
curl -X POST http://localhost:8000/benchmarks/start \
  -H "Content-Type: application/json" \
  -d '{
    "test_type": "http",
    "mesh_type": "baseline",
    "duration": 30
  }'
```

### 3. Test Frontend API Client
```typescript
// In Svelte component
import { benchmarkAPI } from '$lib/api';

const result = await benchmarkAPI.start({
  test_type: 'http',
  mesh_type: 'istio',
  duration: 60
});
console.log(result.data);
```

---

## Monitoring

Access at http://localhost:3000:
- **Grafana**: Visualize metrics
- **Prometheus**: Query time-series data
- **Logs**: `docker-compose logs -f`

---

## Troubleshooting

### Frontend Can't Connect to API

```bash
# Check CORS settings in .env
ALLOWED_ORIGINS=http://localhost:5173

# Verify API is running
curl http://localhost:8000/health

# Check browser console for errors
```

### eBPF Probe Fails

```bash
# Check kernel version
uname -r  # Must be 5.8+

# Verify capabilities
docker run --privileged benchmark-api capsh --print

# Rebuild probes
cd src/probes/latency && ./build.sh
```

---

## Next Steps

1. ✅ Backend API functional
2. ✅ Database integrated
3. ✅ eBPF probes compiled
4. 🔨 Build Svelte frontend
5. 🔨 Add real-time WebSocket updates
6. 🔨 Implement authentication
7. 🔨 Deploy to production

---

**Frontend Stack**: SvelteKit + TypeScript + TailwindCSS + Chart.js
**Backend Stack**: FastAPI + PostgreSQL + Redis + eBPF
**Infrastructure**: Docker Compose + Kubernetes

**Last Updated**: 2025-10-31
