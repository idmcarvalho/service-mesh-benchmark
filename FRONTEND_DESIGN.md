# Service Mesh Benchmark Dashboard - Frontend Design

## Executive Summary

A modern, real-time web dashboard for visualizing service mesh benchmark results, managing test execution, and comparing performance metrics across different service mesh implementations.

---

## 1. Architecture Overview

### Technology Stack

#### Core Framework
- **Frontend Framework**: React 18+ with TypeScript
- **Build Tool**: Vite 5.x (fast HMR, optimized builds)
- **State Management**: Zustand (lightweight) + React Query (data fetching)
- **Routing**: React Router v6

#### UI/UX
- **Component Library**: shadcn/ui (Tailwind-based, customizable)
- **Styling**: Tailwind CSS 3.x
- **Charts**: Recharts + D3.js (for complex visualizations)
- **Icons**: Lucide React
- **Animations**: Framer Motion

#### Backend Integration
- **API Client**: Axios with interceptors
- **Real-time**: Server-Sent Events (SSE) or WebSocket
- **Data Format**: JSON

#### Development Tools
- **Linting**: ESLint with TypeScript rules
- **Formatting**: Prettier
- **Testing**: Vitest + React Testing Library
- **E2E**: Playwright

---

## 2. Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     Browser (Client)                        │
├─────────────────────────────────────────────────────────────┤
│  ┌───────────────────────────────────────────────────────┐  │
│  │              React Application                        │  │
│  ├───────────────────────────────────────────────────────┤  │
│  │  Dashboard │ Test Runner │ Comparison │ Settings     │  │
│  │  ─────────────────────────────────────────────────    │  │
│  │  • Live Metrics    • Test Config   • Charts         │  │
│  │  • Status Cards    • Execution     • Tables         │  │
│  │  • Logs Stream     • Progress      • Export         │  │
│  └──────────────┬────────────────────────────────────────┘  │
│                 │                                            │
│                 │ HTTP REST / SSE                            │
│                 │                                            │
└─────────────────┼────────────────────────────────────────────┘
                  │
┌─────────────────▼────────────────────────────────────────────┐
│                   Backend API Server                         │
├──────────────────────────────────────────────────────────────┤
│  FastAPI or Flask (Python)                                   │
│  ┌────────────────┬────────────────┬─────────────────┐      │
│  │ REST Endpoints │ SSE Stream     │ Background Jobs │      │
│  │ • /api/tests   │ • /api/stream  │ • Test Executor │      │
│  │ • /api/results │ • /api/logs    │ • Metric Poller │      │
│  └────────┬───────┴───────┬────────┴────────┬────────┘      │
│           │               │                 │                │
└───────────┼───────────────┼─────────────────┼────────────────┘
            │               │                 │
            ▼               ▼                 ▼
  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
  │  Kubernetes  │  │   Results    │  │    Redis     │
  │     API      │  │    Files     │  │   (Cache)    │
  └──────────────┘  └──────────────┘  └──────────────┘
```

---

## 3. Page Structure

### 3.1 Dashboard (Home)

**Route**: `/`

**Purpose**: Overview of current cluster status and recent test results

**Layout**:
```
┌──────────────────────────────────────────────────────────┐
│ 🏠 Dashboard                          [User] [Settings]  │
├──────────────────────────────────────────────────────────┤
│                                                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │  Cluster    │  │   Active    │  │   Tests     │     │
│  │  Status     │  │   Mesh      │  │  Completed  │     │
│  │  ✅ Healthy │  │   Istio     │  │    127      │     │
│  │  3/3 Nodes  │  │   v1.20.0   │  │             │     │
│  └─────────────┘  └─────────────┘  └─────────────┘     │
│                                                           │
│  ┌───────────────────────────────────────────────────┐  │
│  │  Recent Test Results                              │  │
│  ├───────────────────────────────────────────────────┤  │
│  │  📊 HTTP Latency Comparison                       │  │
│  │  [Line Chart: Baseline vs Istio vs Cilium]      │  │
│  │  • Baseline: 12ms                                 │  │
│  │  • Istio: 15ms (+25%)                            │  │
│  │  • Cilium: 13ms (+8%)                            │  │
│  │  • Consul: 14ms (+16%)                           │  │
│  └───────────────────────────────────────────────────┘  │
│                                                           │
│  ┌──────────────────────┐  ┌──────────────────────┐    │
│  │  Resource Usage      │  │  Running Tests       │    │
│  │  [Gauge Charts]      │  │  • Phase 4: Istio    │    │
│  │  CPU: 45%            │  │    Progress: 67%     │    │
│  │  Memory: 62%         │  │  • Phase 6: Compare  │    │
│  └──────────────────────┘  │    Queued            │    │
│                             └──────────────────────┘    │
└──────────────────────────────────────────────────────────┘
```

**Components**:
- Status cards with real-time updates
- Interactive charts (Recharts)
- Test execution progress bars
- Quick actions (Run Test, View Results)

### 3.2 Test Runner

**Route**: `/tests/new`

**Purpose**: Configure and execute benchmark tests

**Layout**:
```
┌──────────────────────────────────────────────────────────┐
│ 🧪 Test Configuration                                     │
├──────────────────────────────────────────────────────────┤
│                                                           │
│  Step 1: Select Test Type                                │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐      │
│  │  HTTP   │ │  gRPC   │ │  WebSkt │ │  Full   │      │
│  │  Load   │ │  Load   │ │  Stress │ │  Suite  │      │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘      │
│      ✅                                                   │
│                                                           │
│  Step 2: Select Service Mesh                             │
│  ┌──────────────────────────────────────────────────┐   │
│  │  [ ] Baseline (No mesh)                          │   │
│  │  [✓] Istio    v1.20.0                            │   │
│  │  [✓] Cilium   v1.14.4                            │   │
│  │  [ ] Linkerd  v2.14.0                            │   │
│  │  [✓] Consul   v1.17.0                            │   │
│  └──────────────────────────────────────────────────┘   │
│                                                           │
│  Step 3: Configure Parameters                            │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Test Duration:      [60     ] seconds           │   │
│  │  Connections:        [100    ]                   │   │
│  │  Threads:            [4      ]                   │   │
│  │  Warm-up Duration:   [10     ] seconds           │   │
│  └──────────────────────────────────────────────────┘   │
│                                                           │
│  Advanced Options  [▼]                                   │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Request Timeout:    [10     ] seconds           │   │
│  │  Rate Limit:         [      ] (unlimited)        │   │
│  │  Custom Headers:     [+ Add header]              │   │
│  │  TLS Verification:   [✓] Enabled                 │   │
│  └──────────────────────────────────────────────────┘   │
│                                                           │
│  [Cancel]  [Save Config]  [▶ Run Test]                  │
└──────────────────────────────────────────────────────────┘
```

**Features**:
- Multi-step wizard
- Form validation with Zod
- Save/load configurations
- Real-time parameter preview
- Estimated completion time

### 3.3 Test Execution View

**Route**: `/tests/:id/running`

**Purpose**: Monitor live test execution

**Layout**:
```
┌──────────────────────────────────────────────────────────┐
│ 🔄 Test Execution: HTTP Load - Istio                     │
├──────────────────────────────────────────────────────────┤
│  Status: Running ●  Started: 2m ago  ETA: 1m 12s        │
│                                                           │
│  ┌───────────────────────────────────────────────────┐  │
│  │  Overall Progress                    [  67%  ]    │  │
│  │  ████████████████████░░░░░░░░░░░░░░░░             │  │
│  └───────────────────────────────────────────────────┘  │
│                                                           │
│  ┌───────────────────────────────────────────────────┐  │
│  │  Phase Progress                                    │  │
│  │  ✅ Phase 1: Pre-deployment                        │  │
│  │  ✅ Phase 2: Infrastructure                        │  │
│  │  ✅ Phase 3: Baseline                              │  │
│  │  🔄 Phase 4: Service Mesh (67%)                    │  │
│  │  ⏸  Phase 6: Comparison                            │  │
│  │  ⏸  Phase 7: Stress                                │  │
│  └───────────────────────────────────────────────────┘  │
│                                                           │
│  ┌─────────────────┬─────────────────────────────────┐  │
│  │ Live Metrics    │  Real-time Logs                 │  │
│  │                 │  ───────────────────────────────  │  │
│  │  Requests/sec   │  [12:34:56] Starting test...     │  │
│  │  [Line Chart]   │  [12:34:57] Deploying pods...    │  │
│  │   📈 1,234      │  [12:35:12] Pods ready           │  │
│  │                 │  [12:35:15] Running benchmark... │  │
│  │  Latency p95    │  [12:35:30] Collecting metrics  │  │
│  │  [Area Chart]   │  [Auto-scroll] 🔽               │  │
│  │   ⚡ 18ms       │                                   │  │
│  │                 │                                   │  │
│  │  Error Rate     │                                   │  │
│  │  [Gauge]        │                                   │  │
│  │   ✅ 0.01%     │                                   │  │
│  └─────────────────┴─────────────────────────────────┘  │
│                                                           │
│  [⏸ Pause]  [⏹ Stop]  [📋 View Raw Logs]              │
└──────────────────────────────────────────────────────────┘
```

**Features**:
- Server-Sent Events for real-time updates
- Live charts with streaming data
- Log viewer with filtering
- Pause/resume/stop controls
- Export logs button

### 3.4 Results Comparison

**Route**: `/results/compare`

**Purpose**: Compare results across different service meshes

**Layout**:
```
┌──────────────────────────────────────────────────────────┐
│ 📊 Comparative Analysis                                   │
├──────────────────────────────────────────────────────────┤
│  Select Tests to Compare:                                │
│  [Test 1: HTTP Load - Baseline ▼]  [Test 2: Istio ▼]   │
│  [Test 3: Cilium ▼]  [Test 4: Consul ▼]  [+ Add]       │
│                                                           │
│  ┌───────────────────────────────────────────────────┐  │
│  │  Latency Comparison                               │  │
│  │  ──────────────────────────────────────────────   │  │
│  │  │                                             │  │  │
│  │  │    [Multi-line Chart]                       │  │  │
│  │  │    Legend:                                  │  │  │
│  │  │    ── Baseline (12ms avg)                   │  │  │
│  │  │    ── Istio (15ms avg, +25%)               │  │  │
│  │  │    ── Cilium (13ms avg, +8%)               │  │  │
│  │  │    ── Consul (14ms avg, +16%)              │  │  │
│  │  │                                             │  │  │
│  └───────────────────────────────────────────────────┘  │
│                                                           │
│  ┌───────────────────────────────────────────────────┐  │
│  │  Performance Summary Table                        │  │
│  ├───────────┬──────────┬──────────┬──────────┬──────┤  │
│  │ Mesh      │ Latency  │ Through  │ CPU      │ Mem  │  │
│  │           │ p95 (ms) │ (req/s)  │ (cores)  │ (GB) │  │
│  ├───────────┼──────────┼──────────┼──────────┼──────┤  │
│  │ Baseline  │   12     │  8,500   │   0.5    │  1.2 │  │
│  │ Istio     │   15↑    │  7,200↓  │   1.8↑   │  3.5↑│  │
│  │ Cilium    │   13↑    │  8,100↓  │   0.9↑   │  1.8↑│  │
│  │ Consul    │   14↑    │  7,800↓  │   1.2↑   │  2.4↑│  │
│  └───────────┴──────────┴──────────┴──────────┴──────┘  │
│                                                           │
│  ┌──────────────────────┐  ┌──────────────────────┐    │
│  │  Resource Overhead   │  │  Recommendation      │    │
│  │  [Stacked Bar Chart] │  │  ──────────────────  │    │
│  │                      │  │  Best Latency:       │    │
│  │  Control Plane       │  │  ✅ Cilium (+8%)    │    │
│  │  Data Plane          │  │                      │    │
│  │                      │  │  Best Throughput:    │    │
│  │                      │  │  ✅ Cilium (-4.7%)  │    │
│  │                      │  │                      │    │
│  │                      │  │  Lowest Overhead:    │    │
│  │                      │  │  ✅ Cilium           │    │
│  └──────────────────────┘  └──────────────────────┘    │
│                                                           │
│  [📥 Export CSV]  [📥 Export PDF]  [🔗 Share Link]     │
└──────────────────────────────────────────────────────────┘
```

**Features**:
- Multi-test selection
- Interactive charts (zoom, pan, tooltip)
- Sortable data table
- Export in multiple formats
- Shareable comparison links

### 3.5 Historical Trends

**Route**: `/results/history`

**Purpose**: View trends over time

**Layout**:
```
┌──────────────────────────────────────────────────────────┐
│ 📈 Historical Trends                                      │
├──────────────────────────────────────────────────────────┤
│  Time Range: [Last 7 Days ▼]  Metric: [Latency p95 ▼]  │
│  Mesh: [All ▼]  Test Type: [HTTP Load ▼]               │
│                                                           │
│  ┌───────────────────────────────────────────────────┐  │
│  │  Latency Trend (Last 7 Days)                      │  │
│  │  ──────────────────────────────────────────────   │  │
│  │  20ms ┤                                           │  │
│  │       │        ╱╲                                 │  │
│  │  15ms ┤    ╱╲ ╱  ╲      ╱╲                       │  │
│  │       │  ╱    ╲    ╲  ╱    ╲                     │  │
│  │  10ms ┤╱            ╲╱        ╲                   │  │
│  │       │                        ╲                  │  │
│  │   5ms ┤                          ╲                │  │
│  │       └─┬────┬────┬────┬────┬────┬────┬────      │  │
│  │        Mon  Tue  Wed  Thu  Fri  Sat  Sun         │  │
│  └───────────────────────────────────────────────────┘  │
│                                                           │
│  ┌───────────────────────────────────────────────────┐  │
│  │  Test History Table                               │  │
│  ├─────────┬──────────┬──────────┬──────────┬───────┤  │
│  │ Date    │ Test     │ Mesh     │ Latency  │ View  │  │
│  ├─────────┼──────────┼──────────┼──────────┼───────┤  │
│  │ Dec 28  │ HTTP     │ Istio    │ 15ms     │ [👁]  │  │
│  │ Dec 27  │ HTTP     │ Cilium   │ 13ms     │ [👁]  │  │
│  │ Dec 26  │ gRPC     │ Consul   │ 8ms      │ [👁]  │  │
│  │ Dec 25  │ Full     │ Baseline │ 12ms     │ [👁]  │  │
│  └─────────┴──────────┴──────────┴──────────┴───────┘  │
│                                                           │
│  [Pagination: 1 2 3 ... 10]                              │
└──────────────────────────────────────────────────────────┘
```

### 3.6 Infrastructure View

**Route**: `/infrastructure`

**Purpose**: Monitor cluster health and resources

**Layout**:
```
┌──────────────────────────────────────────────────────────┐
│ 🏗️  Infrastructure                                        │
├──────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────┐ │
│  │  Cluster Topology                                  │ │
│  │                                                     │ │
│  │      ┌──────────┐                                  │ │
│  │      │  Master  │                                  │ │
│  │      │  Node    │                                  │ │
│  │      │  ●       │                                  │ │
│  │      └─────┬────┘                                  │ │
│  │            │                                        │ │
│  │     ┌──────┴──────┐                                │ │
│  │     │             │                                │ │
│  │ ┌───▼───┐    ┌───▼───┐                            │ │
│  │ │Worker1│    │Worker2│                            │ │
│  │ │  ●    │    │  ●    │                            │ │
│  │ └───────┘    └───────┘                            │ │
│  └────────────────────────────────────────────────────┘ │
│                                                           │
│  ┌──────────────────────┐  ┌──────────────────────┐    │
│  │  Node Resources      │  │  Pod Distribution    │    │
│  │  ────────────────    │  │  ──────────────────  │    │
│  │  Master:             │  │  http-benchmark: 5   │    │
│  │  CPU: 45% [██████  ]│  │  grpc-benchmark: 3   │    │
│  │  Mem: 62% [████████]│  │  istio-system: 8     │    │
│  │                      │  │  default: 2          │    │
│  │  Worker-1:           │  │                      │    │
│  │  CPU: 67% [████████]│  │  [Pie Chart]         │    │
│  │  Mem: 54% [██████  ]│  │                      │    │
│  │                      │  │                      │    │
│  │  Worker-2:           │  │                      │    │
│  │  CPU: 52% [██████  ]│  │                      │    │
│  │  Mem: 48% [█████   ]│  │                      │    │
│  └──────────────────────┘  └──────────────────────┘    │
│                                                           │
│  ┌───────────────────────────────────────────────────┐  │
│  │  Service Mesh Components                          │  │
│  ├────────────┬─────────┬──────────┬─────────────────┤  │
│  │ Component  │ Status  │ Version  │ Resources       │  │
│  ├────────────┼─────────┼──────────┼─────────────────┤  │
│  │ istiod     │ ✅ Up   │ 1.20.0   │ CPU: 0.5 Mem:1GB│  │
│  │ gateway    │ ✅ Up   │ 1.20.0   │ CPU: 0.2 Mem:512│  │
│  │ pilot      │ ✅ Up   │ 1.20.0   │ CPU: 0.3 Mem:1GB│  │
│  └────────────┴─────────┴──────────┴─────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

---

## 4. Component Architecture

### 4.1 Core Components

```typescript
// src/components/Dashboard/StatusCard.tsx
interface StatusCardProps {
  title: string;
  value: string | number;
  icon: React.ReactNode;
  trend?: {
    value: number;
    direction: 'up' | 'down';
  };
  status?: 'healthy' | 'warning' | 'error';
}

export const StatusCard: React.FC<StatusCardProps> = ({
  title,
  value,
  icon,
  trend,
  status = 'healthy'
}) => {
  // Implementation
};

// src/components/Charts/LatencyChart.tsx
interface LatencyChartProps {
  data: MetricDataPoint[];
  meshTypes: string[];
  height?: number;
  showLegend?: boolean;
}

export const LatencyChart: React.FC<LatencyChartProps> = ({
  data,
  meshTypes,
  height = 400,
  showLegend = true
}) => {
  // Recharts implementation
};

// src/components/TestRunner/TestWizard.tsx
export const TestWizard: React.FC = () => {
  const [currentStep, setCurrentStep] = useState(1);
  const [config, setConfig] = useState<TestConfig>({});

  const steps = [
    { id: 1, name: 'Test Type', component: TestTypeSelector },
    { id: 2, name: 'Service Mesh', component: MeshSelector },
    { id: 3, name: 'Parameters', component: ParameterForm },
    { id: 4, name: 'Review', component: ConfigReview }
  ];

  return (
    <WizardContainer steps={steps} currentStep={currentStep}>
      {/* Render current step */}
    </WizardContainer>
  );
};
```

### 4.2 State Management

```typescript
// src/stores/testStore.ts
import { create } from 'zustand';
import { devtools, persist } from 'zustand/middleware';

interface TestState {
  tests: Test[];
  currentTest: Test | null;
  isRunning: boolean;

  // Actions
  startTest: (config: TestConfig) => Promise<void>;
  stopTest: (testId: string) => Promise<void>;
  fetchTests: () => Promise<void>;
  subscribeToTestUpdates: (testId: string) => EventSource;
}

export const useTestStore = create<TestState>()(
  devtools(
    persist(
      (set, get) => ({
        tests: [],
        currentTest: null,
        isRunning: false,

        startTest: async (config) => {
          const response = await api.post('/tests/start', config);
          set({ currentTest: response.data, isRunning: true });
        },

        stopTest: async (testId) => {
          await api.post(`/tests/${testId}/stop`);
          set({ isRunning: false });
        },

        fetchTests: async () => {
          const response = await api.get('/tests');
          set({ tests: response.data });
        },

        subscribeToTestUpdates: (testId) => {
          const eventSource = new EventSource(
            `/api/tests/${testId}/stream`
          );

          eventSource.onmessage = (event) => {
            const update = JSON.parse(event.data);
            set((state) => ({
              currentTest: {
                ...state.currentTest,
                ...update
              }
            }));
          };

          return eventSource;
        }
      }),
      { name: 'test-storage' }
    )
  )
);

// src/stores/clusterStore.ts
interface ClusterState {
  nodes: Node[];
  meshStatus: MeshStatus;
  metrics: ClusterMetrics;

  fetchClusterStatus: () => Promise<void>;
}

export const useClusterStore = create<ClusterState>()(
  devtools((set) => ({
    nodes: [],
    meshStatus: {},
    metrics: {},

    fetchClusterStatus: async () => {
      const [nodes, meshStatus, metrics] = await Promise.all([
        api.get('/cluster/nodes'),
        api.get('/cluster/mesh-status'),
        api.get('/cluster/metrics')
      ]);

      set({
        nodes: nodes.data,
        meshStatus: meshStatus.data,
        metrics: metrics.data
      });
    }
  }))
);
```

### 4.3 API Integration

```typescript
// src/lib/api.ts
import axios from 'axios';

const api = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL || '/api',
  timeout: 30000,
  headers: {
    'Content-Type': 'application/json'
  }
});

// Request interceptor
api.interceptors.request.use(
  (config) => {
    const token = localStorage.getItem('auth_token');
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  },
  (error) => Promise.reject(error)
);

// Response interceptor
api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      // Handle unauthorized
      window.location.href = '/login';
    }
    return Promise.reject(error);
  }
);

export default api;

// src/lib/hooks/useTestQuery.ts
import { useQuery } from '@tanstack/react-query';
import api from '../api';

export const useTests = () => {
  return useQuery({
    queryKey: ['tests'],
    queryFn: async () => {
      const response = await api.get('/tests');
      return response.data;
    },
    refetchInterval: 5000 // Refetch every 5 seconds
  });
};

export const useTestDetails = (testId: string) => {
  return useQuery({
    queryKey: ['tests', testId],
    queryFn: async () => {
      const response = await api.get(`/tests/${testId}`);
      return response.data;
    },
    enabled: !!testId
  });
};

export const useTestStream = (testId: string) => {
  const [data, setData] = useState<StreamData | null>(null);

  useEffect(() => {
    const eventSource = new EventSource(`/api/tests/${testId}/stream`);

    eventSource.onmessage = (event) => {
      setData(JSON.parse(event.data));
    };

    eventSource.onerror = () => {
      eventSource.close();
    };

    return () => {
      eventSource.close();
    };
  }, [testId]);

  return data;
};
```

---

## 5. Backend API Specification

### 5.1 REST Endpoints

```python
# backend/app/main.py
from fastapi import FastAPI, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from sse_starlette.sse import EventSourceResponse

app = FastAPI(title="Service Mesh Benchmark API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173"],  # Vite dev server
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Endpoints
@app.get("/api/cluster/status")
async def get_cluster_status():
    """Get current cluster status"""
    return {
        "nodes": [...],
        "mesh": {...},
        "health": "healthy"
    }

@app.post("/api/tests/start")
async def start_test(config: TestConfig, background_tasks: BackgroundTasks):
    """Start a new benchmark test"""
    test_id = generate_test_id()
    background_tasks.add_task(run_test, test_id, config)
    return {"test_id": test_id, "status": "started"}

@app.get("/api/tests/{test_id}/stream")
async def test_stream(test_id: str):
    """Server-Sent Events for test progress"""
    async def event_generator():
        while True:
            # Fetch latest test data
            data = await get_test_progress(test_id)
            yield {
                "event": "progress",
                "data": json.dumps(data)
            }
            await asyncio.sleep(1)

            if data["status"] == "completed":
                break

    return EventSourceResponse(event_generator())

@app.get("/api/results/compare")
async def compare_results(test_ids: List[str]):
    """Compare results from multiple tests"""
    results = await fetch_test_results(test_ids)
    return generate_comparison(results)

@app.get("/api/results/history")
async def get_history(
    days: int = 7,
    mesh_type: Optional[str] = None
):
    """Get historical test results"""
    return await fetch_historical_results(days, mesh_type)
```

### 5.2 Data Models

```typescript
// src/types/test.ts
export interface Test {
  id: string;
  name: string;
  type: 'http' | 'grpc' | 'websocket' | 'full';
  meshType: 'baseline' | 'istio' | 'cilium' | 'linkerd' | 'consul';
  status: 'pending' | 'running' | 'completed' | 'failed';
  config: TestConfig;
  results?: TestResults;
  createdAt: string;
  completedAt?: string;
  duration?: number;
}

export interface TestConfig {
  testType: string;
  meshTypes: string[];
  duration: number;
  connections: number;
  threads: number;
  warmupDuration: number;
  advancedOptions?: {
    timeout?: number;
    rateLimit?: number;
    headers?: Record<string, string>;
    tlsVerification?: boolean;
  };
}

export interface TestResults {
  metrics: {
    latencyP50: number;
    latencyP95: number;
    latencyP99: number;
    throughput: number;
    errorRate: number;
  };
  resources: {
    cpuUsage: number;
    memoryUsage: number;
    controlPlane: ResourceMetrics;
    dataPlane: ResourceMetrics;
  };
  phases: PhaseResult[];
}

export interface MetricDataPoint {
  timestamp: number;
  value: number;
  label?: string;
}

// src/types/cluster.ts
export interface ClusterStatus {
  nodes: Node[];
  health: 'healthy' | 'degraded' | 'unhealthy';
  version: string;
  meshInstalled: string[];
}

export interface Node {
  name: string;
  role: 'master' | 'worker';
  status: 'Ready' | 'NotReady';
  cpu: ResourceUsage;
  memory: ResourceUsage;
  pods: number;
}

export interface ResourceUsage {
  used: number;
  total: number;
  percentage: number;
}
```

---

## 6. Implementation Roadmap

### Phase 1: Foundation (Week 1-2)
- [ ] Setup Vite + React + TypeScript project
- [ ] Configure Tailwind CSS
- [ ] Install shadcn/ui components
- [ ] Setup React Router
- [ ] Implement basic layout (Header, Sidebar, Content)
- [ ] Create API client with Axios
- [ ] Setup Zustand stores

### Phase 2: Core Features (Week 3-4)
- [ ] Dashboard page with status cards
- [ ] Basic chart components (Recharts)
- [ ] Test configuration wizard
- [ ] Test execution view with progress
- [ ] Results display page

### Phase 3: Advanced Features (Week 5-6)
- [ ] Real-time updates with SSE
- [ ] Interactive comparison charts
- [ ] Historical trends view
- [ ] Infrastructure monitoring
- [ ] Export functionality (CSV, PDF)

### Phase 4: Polish & Testing (Week 7-8)
- [ ] Responsive design for mobile/tablet
- [ ] Dark mode support
- [ ] Unit tests (Vitest)
- [ ] E2E tests (Playwright)
- [ ] Performance optimization
- [ ] Documentation

---

## 7. Development Setup

```bash
# Create project
npm create vite@latest benchmark-dashboard -- --template react-ts
cd benchmark-dashboard

# Install dependencies
npm install

# UI Components
npm install @radix-ui/react-dialog @radix-ui/react-dropdown-menu
npm install @radix-ui/react-tabs @radix-ui/react-tooltip
npm install lucide-react class-variance-authority clsx tailwind-merge

# Charts & Visualization
npm install recharts d3

# State & Data
npm install zustand @tanstack/react-query axios

# Routing
npm install react-router-dom

# Forms
npm install react-hook-form zod @hookform/resolvers

# Styling
npm install -D tailwindcss postcss autoprefixer
npm install -D @tailwindcss/forms @tailwindcss/typography

# Testing
npm install -D vitest @testing-library/react @testing-library/jest-dom
npm install -D @playwright/test

# Development
npm install -D eslint prettier eslint-config-prettier
npm install -D @typescript-eslint/eslint-plugin @typescript-eslint/parser

# Initialize Tailwind
npx tailwindcss init -p

# Run dev server
npm run dev
```

### Project Structure

```
benchmark-dashboard/
├── src/
│   ├── components/
│   │   ├── ui/               # shadcn/ui components
│   │   ├── Dashboard/
│   │   ├── TestRunner/
│   │   ├── Charts/
│   │   ├── Infrastructure/
│   │   └── Layout/
│   ├── lib/
│   │   ├── api.ts
│   │   ├── utils.ts
│   │   └── hooks/
│   ├── stores/
│   │   ├── testStore.ts
│   │   ├── clusterStore.ts
│   │   └── uiStore.ts
│   ├── types/
│   │   ├── test.ts
│   │   ├── cluster.ts
│   │   └── api.ts
│   ├── pages/
│   │   ├── Dashboard.tsx
│   │   ├── TestRunner.tsx
│   │   ├── Results.tsx
│   │   ├── Compare.tsx
│   │   ├── History.tsx
│   │   └── Infrastructure.tsx
│   ├── App.tsx
│   └── main.tsx
├── public/
├── tests/
│   ├── unit/
│   └── e2e/
├── package.json
├── vite.config.ts
├── tailwind.config.js
└── tsconfig.json
```

---

## 8. Deployment

### Docker Compose Setup

```yaml
# docker-compose.yml
version: '3.8'

services:
  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
    ports:
      - "80:80"
    environment:
      - VITE_API_BASE_URL=http://localhost:8000/api
    depends_on:
      - backend

  backend:
    build:
      context: .
      dockerfile: backend/Dockerfile
    ports:
      - "8000:8000"
    environment:
      - KUBECONFIG=/root/.kube/config
    volumes:
      - ~/.kube:/root/.kube:ro
      - ./benchmarks/results:/app/results

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
```

### Frontend Dockerfile

```dockerfile
# frontend/Dockerfile
FROM node:20-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

# Production stage
FROM nginx:alpine

COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
```

---

## 9. Security Considerations

### Frontend Security

```typescript
// Sanitize user input
import DOMPurify from 'dompurify';

const sanitizeInput = (input: string): string => {
  return DOMPurify.sanitize(input);
};

// CSP headers in nginx.conf
add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline';";
add_header X-Frame-Options "DENY";
add_header X-Content-Type-Options "nosniff";
add_header Referrer-Policy "strict-origin-when-cross-origin";

// API authentication
const authApi = axios.create({
  baseURL: '/api',
  headers: {
    'X-CSRF-Token': getCsrfToken()
  }
});
```

---

## 10. Future Enhancements

1. **AI-Powered Insights**
   - Anomaly detection in metrics
   - Performance prediction
   - Automatic optimization recommendations

2. **Collaboration Features**
   - Multi-user access with RBAC
   - Shared dashboards
   - Comments on test results

3. **Advanced Visualizations**
   - 3D cluster topology
   - Flame graphs for performance
   - Network flow diagrams

4. **Mobile App**
   - React Native companion app
   - Push notifications for test completion
   - Quick status checks

---

This comprehensive design provides a solid foundation for building a modern, professional dashboard for the Service Mesh Benchmark project!
