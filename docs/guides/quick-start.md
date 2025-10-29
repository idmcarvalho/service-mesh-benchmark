# Service Mesh Benchmark - Quick Start

**Status**: ✅ Production Ready | **Version**: 1.0.0

---

## 🚀 60-Second Setup (Local Development)

```bash
# Clone and start
git clone https://github.com/your-org/service-mesh-benchmark.git
cd service-mesh-benchmark
docker-compose up -d

# Access
open http://localhost:8000/docs  # API
open http://localhost:3000        # Grafana (admin/admin)
open http://localhost:9090        # Prometheus
```

---

## ☁️ Oracle Cloud Deployment (15 Minutes)

### Prerequisites
```bash
# 1. Install tools
brew install terraform kubectl helm ansible  # macOS
# or
sudo apt install terraform kubectl helm ansible  # Linux

# 2. Configure OCI
mkdir -p ~/.oci
# Add your OCI credentials to ~/.oci/config
```

### Deploy
```bash
# 1. Configure
cp terraform/oracle-cloud/terraform.tfvars.example terraform/oracle-cloud/terraform.tfvars
vim terraform/oracle-cloud/terraform.tfvars  # Add your OCI credentials and IP

# 2. Deploy infrastructure (10-15 min)
cd terraform/oracle-cloud
terraform init
terraform apply -auto-approve

# 3. Get kubeconfig
MASTER_IP=$(terraform output -raw master_public_ip)
scp -i ~/.ssh/oci_key ubuntu@$MASTER_IP:~/.kube/config ~/.kube/config-benchmark
export KUBECONFIG=~/.kube/config-benchmark

# 4. Deploy services
kubectl apply -f kubernetes/database/postgres-statefulset.yaml
kubectl wait --for=condition=ready pod/postgres-0 -n benchmark-system --timeout=5m

# 5. Install monitoring
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace --wait

# 6. Choose service mesh
make install-istio    # OR install-cilium, install-consul
```

**✅ Done!** Your cluster is ready.

---

## 📊 Run Your First Benchmark

```bash
# 1. Deploy workloads
make deploy-workloads

# 2. Wait for ready
kubectl get pods -A

# 3. Run benchmark
cd benchmarks/scripts
bash http-load-test.sh

# 4. Check results
ls -lh ../results/

# 5. Generate report
cd ../..
python generate-report.py

# 6. View report
open benchmarks/results/report.html
```

---

## 🔍 Essential Commands

### Health Checks
```bash
# Cluster health
kubectl get nodes

# All pods
kubectl get pods -A

# API health
API_URL=$(kubectl get svc benchmark-api -n benchmark-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl http://$API_URL:8000/health

# Service mesh status
istioctl version       # Istio
cilium status          # Cilium
consul version         # Consul (exec into pod)
```

### Monitoring
```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Open http://localhost:3000 (admin/admin)

# Port-forward Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Open http://localhost:9090

# View logs
kubectl logs -n benchmark-system -l app=benchmark-api --tail=50 -f
```

### Troubleshooting
```bash
# Pod not starting?
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>

# Database connection issues?
kubectl exec -n benchmark-system postgres-0 -- psql -U benchmark -d service_mesh_benchmark -c "SELECT 1;"

# Service mesh not working?
kubectl get pods -n istio-system     # Istio
kubectl get pods -n kube-system -l k8s-app=cilium  # Cilium
kubectl get pods -n consul           # Consul
```

---

## 📦 What's Included

### Infrastructure
- ✅ Terraform for Oracle Cloud (Free Tier)
- ✅ Kubernetes cluster (1 master + 2 workers)
- ✅ PostgreSQL database (StatefulSet)
- ✅ Load balancer

### Application
- ✅ FastAPI REST API
- ✅ 78+ comprehensive tests
- ✅ Job queue (Redis)
- ✅ Result persistence

### Service Meshes
- ✅ Istio (sidecar-based)
- ✅ Cilium (eBPF-based)
- ✅ Linkerd (lightweight)
- ✅ Consul (agent-based)

### Workloads
- ✅ HTTP (nginx + load testing)
- ✅ gRPC (grpcbin + load testing)
- ✅ WebSocket (echo servers)
- ✅ Database (Redis cluster)
- ✅ ML (RandomForest training)

### Monitoring
- ✅ Prometheus (metrics)
- ✅ Grafana (dashboards)
- ✅ Alerting rules
- ✅ 30-day retention

### Operations
- ✅ CI/CD pipeline (GitHub Actions)
- ✅ Automated backups (OCI Object Storage)
- ✅ Secrets management (Sealed Secrets)
- ✅ Deployment runbook

---

## 🛠️ Common Tasks

### Deploy New Version
```bash
# CI/CD does this automatically, or manually:
docker build -t ghcr.io/your-org/api:v1.1.0 -f docker/api/Dockerfile .
docker push ghcr.io/your-org/api:v1.1.0
kubectl set image deployment/benchmark-api api=ghcr.io/your-org/api:v1.1.0 -n benchmark-system
```

### Backup Database
```bash
# Manual backup
kubectl exec -n benchmark-system postgres-0 -- \
  pg_dump -U benchmark service_mesh_benchmark | gzip > backup-$(date +%Y%m%d).sql.gz

# Automated backups run daily at 2 AM UTC
kubectl get cronjobs -n benchmark-system
```

### Scale Components
```bash
# Scale API
kubectl scale deployment benchmark-api --replicas=5 -n benchmark-system

# Scale workers (requires Terraform)
cd terraform/oracle-cloud
terraform apply -var="worker_count=3"
```

### Switch Service Mesh
```bash
# Uninstall current (example: Istio)
istioctl uninstall --purge -y

# Install new (example: Cilium)
make install-cilium

# Re-deploy workloads
make deploy-workloads
```

---

## 📚 Documentation

| Document | Purpose | Link |
|----------|---------|------|
| **Quick Start** | You are here! | [QUICK_START.md](QUICK_START.md) |
| **Production Runbook** | Deployment & operations | [docs/PRODUCTION_DEPLOYMENT_RUNBOOK.md](docs/PRODUCTION_DEPLOYMENT_RUNBOOK.md) |
| **Production Summary** | Implementation details | [PRODUCTION_READY_SUMMARY.md](PRODUCTION_READY_SUMMARY.md) |
| **Testing Guide** | Test execution | [docs/TESTING.md](docs/TESTING.md) |
| **Architecture** | System design | [docs/architecture.md](docs/architecture.md) |
| **API Reference** | API endpoints | http://localhost:8000/docs |
| **Security** | Security measures | [SECURITY_IMPLEMENTATION.md](SECURITY_IMPLEMENTATION.md) |

---

## 💰 Cost

### Free Tier (Oracle Cloud)
- **Monthly Cost**: $0.00
- **Resources**: 4 OCPU, 24GB RAM, 200GB storage
- **Network**: 10TB outbound/month

### Optional Costs
- **Backups**: ~$1-5/month (OCI Object Storage)
- **Total**: < $10/month

---

## 🆘 Getting Help

### Issues?
1. Check [docs/PRODUCTION_DEPLOYMENT_RUNBOOK.md](docs/PRODUCTION_DEPLOYMENT_RUNBOOK.md) troubleshooting section
2. View logs: `kubectl logs -n benchmark-system -l app=benchmark-api`
3. Check health: `curl http://$API_URL:8000/health`
4. Open GitHub issue: https://github.com/your-org/service-mesh-benchmark/issues

### Monitoring
- **Grafana**: http://$GRAFANA_URL:3000
- **Prometheus**: http://$PROMETHEUS_URL:9090
- **API Docs**: http://$API_URL:8000/docs

---

## 🎯 Next Steps

1. **Run benchmarks** → `make test-comprehensive`
2. **View reports** → `open benchmarks/results/report.html`
3. **Compare meshes** → Run tests for each mesh, compare results
4. **Customize** → Modify workloads in `kubernetes/workloads/`
5. **Automate** → Use CI/CD pipeline for continuous benchmarking

---

## ⚡ Pro Tips

```bash
# Quick cluster status
alias k8s-status='kubectl get nodes && kubectl get pods -A | grep -v Running'

# Watch all pods
watch kubectl get pods -A

# Tail API logs
kubectl logs -f -n benchmark-system -l app=benchmark-api --all-containers

# Quick benchmark
make test-baseline && make generate-report && open benchmarks/results/report.html

# Emergency scale down
kubectl scale deployment --all --replicas=0 -n benchmark-system

# Check costs
oci usage-api usage-summary list --compartment-id $OCI_COMPARTMENT_ID --time-usage-started $(date -d '30 days ago' -I)
```

---

## 📊 Performance

- **API Response**: < 100ms (p95)
- **DB Queries**: < 50ms avg
- **Benchmark Duration**: 10s - 1hr (configurable)
- **Deployment Time**: ~15-20 min
- **Backup Time**: ~5-10 min

---

**Ready to benchmark!** 🚀

For detailed information, see [PRODUCTION_READY_SUMMARY.md](PRODUCTION_READY_SUMMARY.md)
