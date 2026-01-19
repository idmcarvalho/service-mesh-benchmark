# Service Mesh Benchmark

A comprehensive benchmarking framework for comparing service mesh performance across different implementations (Istio, Cilium, Linkerd) on Oracle Cloud Infrastructure Free Tier.

## Overview

This project provides an automated infrastructure and testing framework to benchmark various service mesh solutions under different workload patterns:

- **HTTP Services** - RESTful API performance
- **gRPC Services** - RPC protocol efficiency
- **WebSocket Services** - Long-lived connection handling
- **Database Clusters** - Stateful workload performance
- **ML Batch Jobs** - Compute-intensive task execution

## Project Structure

```
service-mesh-benchmark/
├── infrastructure/         # Infrastructure code
│   ├── terraform/          # Infrastructure as Code
│   │   ├── oracle-cloud/   # OCI K8s cluster deployment
│   │   │   ├── main.tf     # VCN, instances, load balancer
│   │   │   ├── variables.tf # Configuration variables
│   │   │   ├── outputs.tf  # Resource outputs
│   │   │   └── versions.tf # Provider requirements
│   │   └── single-instance/ # OCI single instance with Ansible
│   │       ├── main.tf     # Simple single VM deployment
│   │       ├── variables.tf # Configuration variables
│   │       └── outputs.tf  # Resource outputs
│   └── ansible/            # Configuration management
│       ├── playbooks/      # Setup automation
│       └── inventory/      # Host configurations
├── kubernetes/             # Kubernetes manifests
│   ├── workloads/          # Benchmark workloads
│   └── policies/           # Network policies
├── benchmarks/             # Testing scripts
│   ├── scripts/            # Test execution scripts
│   └── results/            # Benchmark results
├── .devcontainer/          # Development container config
├── Makefile                # Automation targets
└── generate-report.py      # Report generation
```

## Prerequisites

- Oracle Cloud Infrastructure account (Free Tier compatible)
- Terraform >= 1.5.0
- kubectl
- Ansible
- Python 3.9+
- SSH key pair

## Quick Start

### 1. Configure OCI Credentials

Copy the example configuration and fill in your OCI credentials:

```bash
cp infrastructure/terraform/oracle-cloud/terraform.tfvars.example infrastructure/terraform/oracle-cloud/terraform.tfvars
```

Edit `terraform.tfvars` with your:
- `tenancy_ocid`
- `user_ocid`
- `fingerprint`
- `private_key_path`
- `compartment_ocid`
- `allowed_ssh_cidr` (your IP address for security)

### 2. Deploy Infrastructure

```bash
# Initialize Terraform
make init

# Validate configuration
make validate

# Deploy infrastructure
make deploy-infra
```

This will create:
- 1 Kubernetes master node
- 2 worker nodes
- VCN with public subnet
- Load balancer
- Security groups (restricted to your IP)

### 3. Configure kubectl

After infrastructure deployment, SSH into the master node and copy the kubeconfig:

```bash
# Get SSH command
cd infrastructure/terraform/oracle-cloud && terraform output ssh_to_master

# SSH and copy kubeconfig to your local machine
scp ubuntu@<master-ip>:~/.kube/config ~/.kube/config-benchmark
export KUBECONFIG=~/.kube/config-benchmark
```

### 4. Install Service Mesh

Choose your service mesh:

```bash
# Option A: Istio
make install-istio

# Option B: Cilium
make install-cilium
```

### 5. Deploy Workloads

```bash
# Deploy all workloads
make deploy-workloads

# Or deploy individual workloads
make deploy-http
make deploy-grpc
make deploy-websocket
make deploy-database
make deploy-ml
```

### 6. Run Benchmarks

```bash
# Run all tests
make test-all

# Or run individual tests
make test-http
make test-grpc
make test-ml
```

### 7. Generate Reports

```bash
# Collect metrics
make collect-metrics

# Generate HTML report
make generate-report

# View report
open benchmarks/results/report.html
```

## Detailed Usage

### Infrastructure Management

```bash
# Show cluster status
make status

# SSH into master node
make ssh-master

# Watch pod status
make watch

# Destroy infrastructure
make destroy
```

### Testing Individual Components

#### HTTP Load Testing

```bash
cd benchmarks/scripts
SERVICE_URL=http-server.http-benchmark.svc.cluster.local \
TEST_DURATION=120 \
CONCURRENT_CONNECTIONS=200 \
bash http-load-test.sh
```

#### gRPC Testing

```bash
cd benchmarks/scripts
SERVICE_URL=grpc-server.grpc-benchmark.svc.cluster.local:9000 \
bash grpc-test.sh
```

#### Metrics Collection

```bash
cd benchmarks/scripts
RESULTS_DIR=../results \
bash collect-metrics.sh
```

### Ansible Automation

```bash
# Configure inventory
cp ansible/inventory/hosts.ini.example ansible/inventory/hosts.ini

# Edit with your instance IPs

# Run tests via Ansible
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/run-tests.yml
```

## Workload Descriptions

### HTTP Service
- **Pods**: 3 replicas of Nginx
- **Client**: 2 replicas generating continuous requests
- **Metrics**: Latency, throughput, error rate
- **Port**: 30080 (NodePort)

### gRPC Service
- **Pods**: 3 replicas of grpcbin
- **Client**: 2 replicas with grpcurl
- **Metrics**: RPC latency, throughput
- **Port**: 30090 (NodePort)

### WebSocket Service
- **Pods**: 3 replicas of echo server
- **Metrics**: Connection stability, message latency
- **Port**: 30808 (NodePort)

### Database Cluster
- **StatefulSet**: 3 Redis instances
- **Client**: 2 replicas running redis-benchmark
- **Metrics**: Read/write latency, throughput

### ML Batch Job
- **Job**: 5 completions, 2 parallel
- **Task**: RandomForest training on synthetic data
- **Metrics**: Completion time, resource usage

## Service Mesh Comparison

The framework allows comparing:

1. **Performance Overhead**
   - Request latency (p50, p95, p99)
   - Throughput degradation
   - CPU/memory overhead

2. **Resource Utilization**
   - Control plane resources
   - Data plane (sidecar) resources
   - Total cluster overhead

3. **Feature Support**
   - Traffic management
   - Observability
   - Security policies

## Cost Optimization

This project is optimized for Oracle Cloud Free Tier:

- **Compute**: Up to 4 OCPUs and 24GB RAM (ARM)
- **Network**: 10TB outbound per month
- **Storage**: 200GB block storage

### Recommended Configuration

```hcl
instance_ocpus = 2      # Master node
instance_memory_gb = 12 # Master node
worker_count = 2        # Worker nodes
worker_ocpus = 1        # Per worker
worker_memory_gb = 6    # Per worker
```

## Development

### Using Dev Container

Open in VS Code with Remote - Containers extension:

```bash
code .
# Reopen in Container when prompted
```

The dev container includes:
- kubectl, helm, terraform
- Benchmark tools (wrk, ghz, grpcurl)
- Python with required packages
- Ansible

### Running Locally with Minikube

```bash
# Start Minikube
minikube start --cpus 4 --memory 8192

# Deploy workloads
kubectl apply -f kubernetes/workloads/

# Run tests
cd benchmarks/scripts && bash http-load-test.sh
```

## Troubleshooting

### Terraform Issues

```bash
# If terraform state is corrupted
cd infrastructure/terraform/oracle-cloud
terraform state list
terraform state rm <resource>

# Refresh state
terraform refresh
```

### Kubernetes Issues

```bash
# Check node status
kubectl get nodes

# Check pod logs
kubectl logs -n http-benchmark <pod-name>

# Describe pod for events
kubectl describe pod -n http-benchmark <pod-name>

# Check service mesh status
istioctl version  # For Istio
cilium status     # For Cilium
```

### Benchmark Script Issues

```bash
# Ensure tools are installed
which wrk ghz grpcurl

# Check service accessibility
kubectl get svc -n http-benchmark
kubectl port-forward -n http-benchmark svc/http-server 8080:80

# Test locally
curl http://localhost:8080
```

## Security Considerations

### Implemented Security Measures
- SSH access restricted to specific CIDR (configure in `terraform.tfvars`)
- Kubernetes API restricted to specific CIDR
- NodePort access can be restricted
- Secrets not committed to version control

### Best Practices

1. **Always** set `allowed_ssh_cidr` to your specific IP
2. **Never** commit `terraform.tfvars` or `*.pem` files
3. **Rotate** SSH keys regularly
4. **Destroy** infrastructure when not in use to minimize exposure
5. **Monitor** OCI billing dashboard for unexpected charges

## Contributing

Contributions welcome! Areas for improvement:

- Additional service mesh implementations (Linkerd, Consul)
- More workload patterns (streaming, event-driven)
- Enhanced metrics collection (distributed tracing)
- Multi-cloud support (AWS, GCP, Azure)
- CI/CD pipeline integration

## License

MIT License - See LICENSE file for details

## Acknowledgments

- Oracle Cloud Infrastructure for Free Tier resources
- Istio, Cilium, and Linkerd communities
- Kubernetes community
- Benchmark tool authors (wrk, ghz, etc.)

## References

- [Istio Documentation](https://istio.io/docs/)
- [Cilium Documentation](https://docs.cilium.io/)
- [Oracle Cloud Free Tier](https://www.oracle.com/cloud/free/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

---

**Note**: This is a research/educational project. For production service mesh deployments, consult official documentation and consider managed services.
