# Service Mesh Benchmark Testing Flow Diagram

## Complete Testing Workflow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         TESTING WORKFLOW OVERVIEW                            │
└─────────────────────────────────────────────────────────────────────────────┘

    ┌──────────────────┐
    │  make test-deps  │  Install Python dependencies
    └────────┬─────────┘
             │
             ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ PHASE 1: PRE-DEPLOYMENT VALIDATION (< 5 min, No Infrastructure)            │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Command: make test-validate                                                │
│                                                                             │
│  ✓ Terraform installed & config valid                                      │
│  ✓ kubectl installed                                                        │
│  ✓ Python dependencies available                                           │
│  ✓ Kubernetes manifests valid                                              │
│  ✓ Benchmark scripts executable                                            │
│  ✓ Health checks defined                                                   │
│  ✓ Resource limits configured                                              │
│  ✓ No hardcoded credentials                                                │
│                                                                             │
│  Result: Environment validated ✅                                           │
└────────┬───────────────────────────────────────────────────────────────────┘
         │
         ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                      INFRASTRUCTURE DEPLOYMENT                              │
├────────────────────────────────────────────────────────────────────────────┤
│  make deploy-infra                                                          │
│  ├─ Terraform creates VCN, compute instances, load balancer                │
│  ├─ Kubernetes cluster initialized (1 master + 2 workers)                  │
│  └─ kubectl configured                                                      │
└────────┬───────────────────────────────────────────────────────────────────┘
         │
         ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ PHASE 2: INFRASTRUCTURE VALIDATION (5-10 min, Requires Cluster)            │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Command: make test-infra                                                   │
│                                                                             │
│  ✓ Kubernetes cluster accessible                                           │
│  ✓ All nodes Ready                                                          │
│  ✓ System pods running (CoreDNS, etc.)                                     │
│  ✓ DNS resolution working                                                   │
│  ✓ Pod-to-pod networking functional                                        │
│  ✓ Storage classes available                                               │
│  ✓ Sufficient node resources                                               │
│  ✓ Proper permissions                                                       │
│                                                                             │
│  Result: Infrastructure ready ✅                                            │
└────────┬───────────────────────────────────────────────────────────────────┘
         │
         ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                        BASELINE PATH                                        │
├────────────────────────────────────────────────────────────────────────────┤
│  make deploy-baseline                                                       │
│  ├─ Deploy HTTP service (no mesh)                                          │
│  ├─ Deploy gRPC service (no mesh)                                          │
│  └─ Wait for pods ready                                                     │
└────────┬───────────────────────────────────────────────────────────────────┘
         │
         ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ PHASE 3: BASELINE TESTING (10-30 min)                                      │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Command: make test-baseline OR make test-full                             │
│                                                                             │
│  ✓ Verify workload deployment                                              │
│  ✓ Test service connectivity                                               │
│  ✓ Validate health endpoints                                               │
│  ✓ Run HTTP load tests (wrk + ab)                                          │
│     └─ Collect latency (p50, p95, p99)                                     │
│     └─ Measure throughput (req/s)                                          │
│  ✓ Run gRPC load tests                                                     │
│  ✓ Measure resource usage (CPU, Memory)                                    │
│  ✓ Verify error rate < 5%                                                  │
│                                                                             │
│  Results Saved:                                                             │
│  ├─ benchmarks/results/baseline_http_metrics.json                          │
│  ├─ benchmarks/results/baseline_grpc_metrics.json                          │
│  └─ benchmarks/results/baseline_resources.json                             │
│                                                                             │
│  Metrics: Latency=5ms, Throughput=5000req/s, CPU=300m, Mem=150Mi           │
└────────┬───────────────────────────────────────────────────────────────────┘
         │
         ├─────────────────────────────────┬─────────────────────────────────┐
         ▼                                 ▼                                 ▼
┌─────────────────────┐       ┌─────────────────────┐       ┌─────────────────────┐
│   ISTIO PATH        │       │   CILIUM PATH       │       │  LINKERD PATH       │
├─────────────────────┤       ├─────────────────────┤       ├─────────────────────┤
│ make install-istio  │       │ make install-cilium │       │make install-linkerd │
│ make deploy-workloads│      │ make deploy-workloads│      │make deploy-workloads│
└──────────┬──────────┘       └──────────┬──────────┘       └──────────┬──────────┘
           │                             │                             │
           ▼                             ▼                             ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ PHASE 4: SERVICE MESH TESTING (15-45 min per mesh)                         │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Commands:                                                                  │
│  ├─ make test-full-istio                                                   │
│  ├─ make test-full-cilium                                                  │
│  └─ make test-full-linkerd                                                 │
│                                                                             │
│  For each mesh:                                                             │
│  ✓ Verify mesh installation (control plane healthy)                        │
│  ✓ Verify sidecar injection OR eBPF programs                               │
│  ✓ Test connectivity through mesh                                          │
│  ✓ Verify mTLS enabled                                                     │
│  ✓ Run same HTTP/gRPC load tests                                           │
│  ✓ Measure control plane resources                                         │
│  ✓ Measure data plane resources                                            │
│  ✓ Calculate overhead vs baseline                                          │
│                                                                             │
│  Results Saved (per mesh):                                                  │
│  ├─ {mesh}_http_metrics.json                                               │
│  ├─ {mesh}_grpc_metrics.json                                               │
│  ├─ {mesh}_overhead.json                                                   │
│  └─ {mesh}_latency_comparison.json                                         │
│                                                                             │
│  Example Istio Metrics:                                                     │
│  Latency=7ms (+40%), Throughput=4200req/s (-16%)                           │
│  Control Plane: CPU=600m, Mem=800Mi                                         │
│  Data Plane: CPU=+100m/pod, Mem=+80Mi/pod                                  │
│                                                                             │
│  Example Cilium Metrics:                                                    │
│  Latency=5.5ms (+10%), Throughput=4750req/s (-5%)                          │
│  Control Plane: CPU=300m, Mem=400Mi                                         │
│  Data Plane: CPU=+50m/pod, Mem=+40Mi/pod                                   │
└────────┬───────────────────────────────────────────────────────────────────┘
         │
         ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ PHASE 6: COMPARATIVE ANALYSIS (< 5 min)                                    │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Command: make test-compare                                                 │
│                                                                             │
│  ✓ Load all metrics files                                                  │
│  ✓ Compare latency across all meshes                                       │
│  ✓ Compare throughput across all meshes                                    │
│  ✓ Compare resource overhead                                               │
│  ✓ Generate comparison tables                                              │
│  ✓ Determine best performers                                               │
│                                                                             │
│  Output:                                                                    │
│  ┌────────────────────────────────────────────────────────┐                │
│  │        LATENCY COMPARISON                              │                │
│  ├─────────────┬──────────────┬────────────┬─────────────┤                │
│  │ Mesh        │ Latency (ms) │ vs Baseline│ Overhead %  │                │
│  ├─────────────┼──────────────┼────────────┼─────────────┤                │
│  │ Baseline    │ 5.00         │ -          │ 0%          │                │
│  │ Cilium      │ 5.50         │ +0.50ms    │ +10.0%      │                │
│  │ Linkerd     │ 6.00         │ +1.00ms    │ +20.0%      │                │
│  │ Istio       │ 7.00         │ +2.00ms    │ +40.0%      │                │
│  └─────────────┴──────────────┴────────────┴─────────────┘                │
│                                                                             │
│  Results Saved:                                                             │
│  ├─ latency_comparison.json                                                │
│  ├─ best_performers.json                                                   │
│  └─ test_summary.json                                                      │
│                                                                             │
│  Best Performers:                                                           │
│  ├─ Lowest Latency: Cilium                                                 │
│  ├─ Highest Throughput: Cilium                                             │
│  ├─ Lowest CPU Overhead: Cilium                                            │
│  └─ Lowest Memory Overhead: Cilium                                         │
└────────┬───────────────────────────────────────────────────────────────────┘
         │
         ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ PHASE 7: STRESS & EDGE CASE TESTING (30-60 min, Optional)                  │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Command: make test-stress MESH_TYPE=<mesh>                                │
│                                                                             │
│  Stress Tests:                                                              │
│  ✓ High concurrent connections (500+ connections)                          │
│  ✓ Extended duration (10 minutes)                                          │
│  ✓ Burst traffic patterns                                                  │
│                                                                             │
│  Failure Scenarios:                                                         │
│  ✓ Pod deletion & recovery                                                 │
│  ✓ Service continuity during failures                                      │
│  ✓ Node resource saturation                                                │
│                                                                             │
│  Security Tests:                                                            │
│  ✓ Network policy enforcement                                              │
│  ✓ mTLS enforcement                                                        │
│  ✓ Authorization policies                                                  │
│                                                                             │
│  Edge Cases:                                                                │
│  ✓ Empty requests                                                          │
│  ✓ Large payloads                                                          │
│  ✓ Cross-namespace access                                                  │
│                                                                             │
│  Result: System reliability validated ✅                                    │
└────────┬───────────────────────────────────────────────────────────────────┘
         │
         ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                         FINAL REPORTING                                     │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Command: make test-report                                                  │
│                                                                             │
│  Generates:                                                                 │
│  ├─ HTML report (benchmarks/results/report.html)                           │
│  ├─ JSON report (benchmarks/results/test_report.json)                      │
│  ├─ Summary (benchmarks/results/test_summary.json)                         │
│  └─ Charts and visualizations                                              │
│                                                                             │
│  View: open benchmarks/results/report.html                                 │
└────────────────────────────────────────────────────────────────────────────┘
```

## Alternative Quick Testing Workflow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    QUICK TESTING WORKFLOW (Dev/CI)                          │
└─────────────────────────────────────────────────────────────────────────────┘

    make test-deps          Install dependencies
         │
         ▼
    make test-validate      Phase 1: Quick validation (< 5 min)
         │                  ├─ No infrastructure needed
         │                  └─ Catches config issues early
         ▼
    make test-quick         Fast tests only (excludes slow tests)
         │                  ├─ Good for development
         │                  └─ Quick feedback loop
         ▼
    make test-ci            CI-friendly test suite
         │                  ├─ Pre-deployment tests
         │                  ├─ Generates HTML/JSON reports
         │                  └─ Exit code for CI/CD
         ▼
       Done ✅
```

## Comprehensive Testing Workflow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│              COMPREHENSIVE TESTING (All Phases, All Meshes)                 │
└─────────────────────────────────────────────────────────────────────────────┘

    make test-comprehensive
         │
         ├─── Phase 1: Pre-deployment validation
         │     └─ make test-validate
         │
         ├─── Phase 2: Infrastructure validation
         │     └─ make test-infra
         │
         ├─── Phase 3: Baseline testing
         │     ├─ make deploy-baseline
         │     └─ make test-full (baseline)
         │
         ├─── Phase 4: Istio testing
         │     ├─ make install-istio
         │     ├─ make deploy-workloads
         │     └─ make test-full-istio
         │
         ├─── Phase 4: Cilium testing
         │     ├─ make clean-workloads
         │     ├─ Uninstall Istio
         │     ├─ make install-cilium
         │     ├─ make deploy-workloads
         │     └─ make test-full-cilium
         │
         └─── Phase 6: Comparative analysis
               └─ make test-compare
                   ├─ Generate comparison tables
                   ├─ Identify best performers
                   └─ Create summary reports

    Total Duration: 2-4 hours (depending on test parameters)
    Result: Complete service mesh comparison ✅
```

## Test Result Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          TEST RESULTS FLOW                                  │
└─────────────────────────────────────────────────────────────────────────────┘

                        Test Execution
                              │
                              ▼
                    ┌─────────────────┐
                    │  Metrics        │
                    │  Collection     │
                    └────────┬────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
    ┌─────────┐       ┌─────────┐       ┌─────────┐
    │ HTTP    │       │ gRPC    │       │Resource │
    │ Metrics │       │ Metrics │       │ Metrics │
    └────┬────┘       └────┬────┘       └────┬────┘
         │                 │                  │
         └─────────────────┼──────────────────┘
                           ▼
                ┌──────────────────────┐
                │  JSON Files          │
                │  benchmarks/results/ │
                ├──────────────────────┤
                │ - baseline_*.json    │
                │ - istio_*.json       │
                │ - cilium_*.json      │
                │ - linkerd_*.json     │
                │ - *_comparison.json  │
                └──────────┬───────────┘
                           │
                           ▼
                ┌──────────────────────┐
                │  Analysis            │
                │  (Phase 6)           │
                ├──────────────────────┤
                │ - Compare latency    │
                │ - Compare throughput │
                │ - Compare overhead   │
                │ - Find best          │
                └──────────┬───────────┘
                           │
                           ▼
                ┌──────────────────────┐
                │  Reports             │
                ├──────────────────────┤
                │ - HTML report        │
                │ - JSON report        │
                │ - Summary            │
                │ - Best performers    │
                └──────────────────────┘
```

## Health Check Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       HEALTH CHECK ARCHITECTURE                             │
└─────────────────────────────────────────────────────────────────────────────┘

    ┌─────────────────────────────────────────────────────────┐
    │                 HTTP Service                             │
    ├─────────────────────────────────────────────────────────┤
    │  ┌─────────────────────────────────────────┐            │
    │  │  Nginx Container                        │            │
    │  ├─────────────────────────────────────────┤            │
    │  │  Endpoints:                             │            │
    │  │  ├─ /         → Benchmark response      │            │
    │  │  └─ /health   → OK (200)                │            │
    │  │                                          │            │
    │  │  Probes:                                 │            │
    │  │  ├─ livenessProbe  → /health            │            │
    │  │  └─ readinessProbe → /health            │            │
    │  └─────────────────────────────────────────┘            │
    └─────────────────────────────────────────────────────────┘

    ┌─────────────────────────────────────────────────────────┐
    │                 gRPC Service                             │
    ├─────────────────────────────────────────────────────────┤
    │  ┌─────────────────────────────────────────┐            │
    │  │  grpcbin Container                      │            │
    │  ├─────────────────────────────────────────┤            │
    │  │  Protocol: gRPC                         │            │
    │  │  Port: 9000                             │            │
    │  │                                          │            │
    │  │  Probes:                                 │            │
    │  │  ├─ livenessProbe  → TCP:9000           │            │
    │  │  └─ readinessProbe → TCP:9000           │            │
    │  └─────────────────────────────────────────┘            │
    └─────────────────────────────────────────────────────────┘

    ┌─────────────────────────────────────────────────────────┐
    │            Health Check Service                          │
    ├─────────────────────────────────────────────────────────┤
    │  ┌─────────────────────────────────────────┐            │
    │  │  Flask + psutil Container               │            │
    │  ├─────────────────────────────────────────┤            │
    │  │  Endpoints:                             │            │
    │  │  ├─ /health  → Basic health check       │            │
    │  │  ├─ /ready   → Readiness check          │            │
    │  │  ├─ /probe   → Comprehensive probe      │            │
    │  │  │             (CPU, Memory, Status)    │            │
    │  │  └─ /metrics → Resource metrics         │            │
    │  │                                          │            │
    │  │  Probes:                                 │            │
    │  │  ├─ livenessProbe  → /health            │            │
    │  │  └─ readinessProbe → /ready             │            │
    │  └─────────────────────────────────────────┘            │
    └─────────────────────────────────────────────────────────┘
```

## Legend

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              LEGEND                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ✓  Test passed                                                             │
│  ✅  Phase/Stage completed successfully                                     │
│  │  Sequential flow                                                         │
│  ├─ Branch/Option                                                           │
│  └─ End of branch                                                           │
│  ▼  Flow direction                                                          │
│                                                                             │
│  [Component]   Process or system component                                  │
│  ┌─────┐      Start/End point                                              │
│  └─────┘                                                                    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```
