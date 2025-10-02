# Service Mesh Benchmark Architecture

## Overview

This document describes the architecture of the service mesh benchmarking framework, including infrastructure components, workload types, and data flow.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     Oracle Cloud Infrastructure                  │
│                          (Free Tier)                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                  Virtual Cloud Network (VCN)              │  │
│  │                      10.0.0.0/16                          │  │
│  │                                                            │  │
│  │  ┌───────────────────────────────────────────────────┐   │  │
│  │  │            Public Subnet (10.0.1.0/24)            │   │  │
│  │  │                                                     │   │  │
│  │  │   ┌─────────────────────────────────────────┐    │   │  │
│  │  │   │      Load Balancer (Flexible 10Mbps)    │    │   │  │
│  │  │   └──────────────┬──────────────────────────┘    │   │  │
│  │  │                  │                                │   │  │
│  │  │   ┌──────────────┴──────────────────────────┐    │   │  │
│  │  │   │                                          │    │   │  │
│  │  │   ▼                                          ▼    │   │  │
│  │  │ ┌──────────────┐    ┌──────────────┐  ┌──────────────┐ │
│  │  │ │ Master Node  │    │ Worker Node 1│  │ Worker Node 2│ │
│  │  │ │  2 OCPU      │    │  1 OCPU      │  │  1 OCPU      │ │
│  │  │ │  12GB RAM    │    │  6GB RAM     │  │  6GB RAM     │ │
│  │  │ │              │    │              │  │              │ │
│  │  │ │ - K8s Master │    │ - K8s Worker │  │ - K8s Worker │ │
│  │  │ │ - etcd       │    │ - kubelet    │  │ - kubelet    │ │
│  │  │ │ - kubectl    │    │ - containerd │  │ - containerd │ │
│  │  │ └──────────────┘    └──────────────┘  └──────────────┘ │
│  │  │                                                     │   │  │
│  │  │   Security Groups:                                 │   │  │
│  │  │   - SSH (22) - Restricted by CIDR                 │   │  │
│  │  │   - K8s API (6443) - Restricted by CIDR           │   │  │
│  │  │   - NodePort (30000-32767) - Configurable         │   │  │
│  │  │   - Internal (all) - 10.0.0.0/16                  │   │  │
│  │  └─────────────────────────────────────────────────┘   │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Kubernetes Cluster Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                       Kubernetes Cluster                            │
├────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Service Mesh Layer (Optional - One of):                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐             │
│  │    Istio     │  │   Cilium     │  │   Linkerd    │             │
│  │              │  │              │  │              │             │
│  │ - Control    │  │ - Operator   │  │ - Control    │             │
│  │   Plane      │  │ - Agents     │  │   Plane      │             │
│  │ - Sidecars   │  │   (eBPF)     │  │ - Proxies    │             │
│  └──────────────┘  └──────────────┘  └──────────────┘             │
│                                                                      │
├────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Workload Namespaces:                                              │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  http-benchmark                                              │  │
│  │  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐    │  │
│  │  │ HTTP Server  │   │ HTTP Server  │   │ HTTP Server  │    │  │
│  │  │   (nginx)    │   │   (nginx)    │   │   (nginx)    │    │  │
│  │  │  x3 replicas │   │              │   │              │    │  │
│  │  └──────────────┘   └──────────────┘   └──────────────┘    │  │
│  │                                                               │  │
│  │  ┌──────────────┐   ┌──────────────┐                        │  │
│  │  │ HTTP Client  │   │ HTTP Client  │                        │  │
│  │  │   (curl)     │   │   (curl)     │                        │  │
│  │  │  x2 replicas │   │              │                        │  │
│  │  └──────────────┘   └──────────────┘                        │  │
│  │                                                               │  │
│  │  Service: ClusterIP (http-server:80)                         │  │
│  │  Service: NodePort (30080)                                   │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  grpc-benchmark                                              │  │
│  │  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐    │  │
│  │  │ gRPC Server  │   │ gRPC Server  │   │ gRPC Server  │    │  │
│  │  │  (grpcbin)   │   │  (grpcbin)   │   │  (grpcbin)   │    │  │
│  │  │  x3 replicas │   │              │   │              │    │  │
│  │  └──────────────┘   └──────────────┘   └──────────────┘    │  │
│  │                                                               │  │
│  │  ┌──────────────┐   ┌──────────────┐                        │  │
│  │  │ gRPC Client  │   │ gRPC Client  │                        │  │
│  │  │  (grpcurl)   │   │  (grpcurl)   │                        │  │
│  │  │  x2 replicas │   │              │                        │  │
│  │  └──────────────┘   └──────────────┘                        │  │
│  │                                                               │  │
│  │  Service: ClusterIP (grpc-server:9000)                       │  │
│  │  Service: NodePort (30090)                                   │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  websocket-benchmark                                         │  │
│  │  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐    │  │
│  │  │  WS Server   │   │  WS Server   │   │  WS Server   │    │  │
│  │  │   (echo)     │   │   (echo)     │   │   (echo)     │    │  │
│  │  │  x3 replicas │   │              │   │              │    │  │
│  │  └──────────────┘   └──────────────┘   └──────────────┘    │  │
│  │                                                               │  │
│  │  Service: ClusterIP (ws-server:8080)                         │  │
│  │  Service: NodePort (30808)                                   │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  db-benchmark (StatefulSet)                                  │  │
│  │  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐    │  │
│  │  │   Redis-0    │   │   Redis-1    │   │   Redis-2    │    │  │
│  │  │              │   │              │   │              │    │  │
│  │  │  + PVC       │   │  + PVC       │   │  + PVC       │    │  │
│  │  └──────────────┘   └──────────────┘   └──────────────┘    │  │
│  │                                                               │  │
│  │  ┌──────────────┐   ┌──────────────┐                        │  │
│  │  │ Redis Client │   │ Redis Client │                        │  │
│  │  │ (benchmark)  │   │ (benchmark)  │                        │  │
│  │  └──────────────┘   └──────────────┘                        │  │
│  │                                                               │  │
│  │  Service: Headless (redis-cluster)                           │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  ml-benchmark (Job)                                          │  │
│  │  ┌──────────────┐   ┌──────────────┐                        │  │
│  │  │   ML Job 1   │   │   ML Job 2   │                        │  │
│  │  │ RandomForest │   │ RandomForest │                        │  │
│  │  │  Training    │   │  Training    │                        │  │
│  │  └──────────────┘   └──────────────┘                        │  │
│  │                                                               │  │
│  │  Completions: 5, Parallelism: 2                              │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  baseline-http / baseline-grpc (No Service Mesh)            │  │
│  │  Same structure as above but without mesh injection         │  │
│  │  Used for baseline performance comparison                    │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                      │
└────────────────────────────────────────────────────────────────────┘
```

## Traffic Flow

### HTTP Request Flow (with Istio Example)

```
┌─────────────┐
│   Client    │
│  (curl pod) │
└──────┬──────┘
       │
       │ 1. HTTP Request
       ▼
┌─────────────────────┐
│  Istio Proxy        │
│  (Client Sidecar)   │
│  - Metrics capture  │
│  - mTLS encryption  │
└──────┬──────────────┘
       │
       │ 2. Encrypted via mTLS
       ▼
┌─────────────────────┐
│  Service Discovery  │
│  (kube-dns)         │
└──────┬──────────────┘
       │
       │ 3. Route to endpoint
       ▼
┌─────────────────────┐
│  Istio Proxy        │
│  (Server Sidecar)   │
│  - mTLS decryption  │
│  - Access control   │
│  - Metrics          │
└──────┬──────────────┘
       │
       │ 4. Forward to app
       ▼
┌─────────────────────┐
│   nginx Server      │
│   (port 80)         │
└─────────────────────┘
```

### Metrics Collection Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Metrics Collection                        │
└─────────────────────────────────────────────────────────────┘
       │
       ├──► Control Plane Metrics
       │    ├─ Istio: istiod CPU/Memory
       │    ├─ Cilium: operator CPU/Memory
       │    └─ Linkerd: controller CPU/Memory
       │
       ├──► Data Plane Metrics
       │    ├─ Sidecar CPU/Memory per pod
       │    ├─ Proxy request count
       │    └─ Connection statistics
       │
       ├──► Application Metrics
       │    ├─ wrk: throughput, latency
       │    ├─ ghz: gRPC RPS, latency
       │    └─ WebSocket: msg/s, latency
       │
       └──► Kubernetes Metrics
            ├─ Node resource usage
            ├─ Pod resource usage
            └─ Service endpoints
```

## Benchmark Execution Flow

```
┌────────────────────┐
│  1. Deploy Infra   │
│   (Terraform)      │
└─────────┬──────────┘
          │
          ▼
┌────────────────────┐
│  2. Setup K8s      │
│   (kubeadm)        │
└─────────┬──────────┘
          │
          ▼
┌────────────────────┐
│  3. Install Mesh   │
│  (Ansible/Helm)    │
└─────────┬──────────┘
          │
          ▼
┌────────────────────┐
│  4. Deploy         │
│     Workloads      │
│  (kubectl apply)   │
└─────────┬──────────┘
          │
          ▼
┌────────────────────┐
│  5. Health Check   │
│  (kubectl wait)    │
└─────────┬──────────┘
          │
          ▼
┌────────────────────┐
│  6. Warm-up        │
│   (10s light load) │
└─────────┬──────────┘
          │
          ▼
┌────────────────────┐
│  7. Run Tests      │
│  (wrk/ghz/custom)  │
└─────────┬──────────┘
          │
          ▼
┌────────────────────┐
│  8. Cool-down      │
│   (5s wait)        │
└─────────┬──────────┘
          │
          ▼
┌────────────────────┐
│  9. Collect        │
│     Metrics        │
│  (collect-metrics) │
└─────────┬──────────┘
          │
          ▼
┌────────────────────┐
│ 10. Generate       │
│     Report         │
│ (generate-report)  │
└────────────────────┘
```

## Component Responsibilities

### Infrastructure Layer (Terraform)
- **VCN & Networking**: Creates isolated network environment
- **Compute Instances**: Provisions ARM-based instances (Free Tier)
- **Security Groups**: Configures firewall rules
- **Load Balancer**: Optional external access point

### Orchestration Layer (Kubernetes)
- **Master Node**: Cluster control plane, scheduling
- **Worker Nodes**: Application workload execution
- **Services**: Internal service discovery and load balancing
- **ConfigMaps/Secrets**: Configuration management

### Service Mesh Layer (Istio/Cilium/Linkerd)
- **Control Plane**: Configuration, policy enforcement, certificate management
- **Data Plane**:
  - Istio: Envoy sidecars
  - Cilium: eBPF agents (no sidecars)
  - Linkerd: Linkerd2-proxy sidecars

### Application Layer
- **HTTP Services**: RESTful API simulation
- **gRPC Services**: RPC protocol testing
- **WebSocket Services**: Long-lived connection testing
- **Database Clusters**: Stateful workload testing
- **ML Jobs**: Compute-intensive batch processing

### Testing Layer
- **Load Generators**: wrk, ghz, custom WebSocket clients
- **Metrics Collectors**: kubectl top, service mesh metrics exporters
- **Result Aggregators**: Shell scripts, Python report generator

## Data Storage

```
benchmarks/
└── results/
    ├── http_test_*.json          # Test metadata
    ├── http_wrk_*.txt            # Raw wrk output
    ├── http_k8s_metrics_*.txt    # K8s resource usage
    ├── grpc_test_*.json          # gRPC test results
    ├── websocket_test_*.json     # WebSocket metrics
    ├── metrics_*.json            # Mesh overhead metrics
    └── report.html               # Generated report
```

## Performance Metrics

### Latency Metrics
- **P50 (Median)**: Middle value of all requests
- **P95**: 95th percentile - only 5% slower
- **P99**: 99th percentile - tail latency
- **Max**: Worst-case latency

### Throughput Metrics
- **Requests/sec**: HTTP/gRPC request rate
- **Messages/sec**: WebSocket throughput
- **Transfer/sec**: Network bandwidth usage

### Resource Metrics
- **Control Plane**: CPU/Memory for mesh controllers
- **Data Plane**: CPU/Memory for sidecars/agents
- **Total Overhead**: Combined mesh resource usage

## Comparison Methodology

1. **Baseline Run**: Deploy workloads without service mesh
2. **Mesh Runs**: Deploy same workloads with each mesh
3. **Multiple Iterations**: Run each test 3-5 times
4. **Statistical Analysis**: Calculate mean, stddev, percentiles
5. **Overhead Calculation**:
   ```
   Overhead % = ((Mesh_Metric - Baseline_Metric) / Baseline_Metric) * 100
   ```

## Security Architecture

- **Network Isolation**: VCN with private subnets
- **CIDR Restrictions**: SSH/API access limited to operator IP
- **No Public Keys in Repo**: Keys excluded via .gitignore
- **mTLS**: Automatic when service mesh is enabled
- **RBAC**: Kubernetes role-based access control

## Scalability Considerations

### Current Limits (Free Tier)
- **Total OCPUs**: 4 ARM cores
- **Total Memory**: 24 GB RAM
- **Storage**: 200 GB block storage
- **Network**: 10 TB/month egress

### Scaling Options
1. Reduce worker count for heavier mesh testing
2. Use smaller workload replicas
3. Sequential testing (one mesh at a time)
4. Upgrade to paid tier for parallel comparison

## Future Enhancements

- **Multi-cloud Support**: AWS, GCP, Azure
- **Additional Meshes**: Consul, Kuma
- **Enhanced Observability**: Prometheus, Grafana integration
- **Distributed Tracing**: Jaeger integration
- **Chaos Engineering**: Fault injection testing
- **Cost Analysis**: Track and report actual OCI costs
