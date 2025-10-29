## Production Deployment Runbook

**Service Mesh Benchmark - Oracle Cloud Infrastructure**

Version: 1.0.0
Last Updated: 2024-10-27

---

## Table of Contents

1. [Pre-Deployment Checklist](#pre-deployment-checklist)
2. [Infrastructure Deployment](#infrastructure-deployment)
3. [Database Setup](#database-setup)
4. [Application Deployment](#application-deployment)
5. [Monitoring Setup](#monitoring-setup)
6. [Service Mesh Installation](#service-mesh-installation)
7. [Post-Deployment Validation](#post-deployment-validation)
8. [Rollback Procedures](#rollback-procedures)
9. [Troubleshooting](#troubleshooting)
10. [Maintenance Procedures](#maintenance-procedures)

---

## Pre-Deployment Checklist

### 1. Required Credentials and Access

- [ ] OCI API credentials configured
  ```bash
  # ~/.oci/config should contain:
  [DEFAULT]
  user=ocid1.user...
  fingerprint=...
  tenancy=ocid1.tenancy...
  region=us-ashburn-1
  key_file=~/.oci/oci_api_key.pem
  ```

- [ ] SSH key pair generated
  ```bash
  ssh-keygen -t rsa -b 4096 -f ~/.ssh/oci_benchmark_key
  ```

- [ ] GitHub Container Registry access
  ```bash
  echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin
  ```

- [ ] kubectl installed (v1.27+)
  ```bash
  kubectl version --client
  ```

- [ ] Terraform installed (v1.5+)
  ```bash
  terraform --version
  ```

### 2. Configuration Files

- [ ] Create `terraform/oracle-cloud/terraform.tfvars`
  ```hcl
  tenancy_ocid     = "ocid1.tenancy.oc1.."
  user_ocid        = "ocid1.user.oc1.."
  fingerprint      = "aa:bb:cc:..."
  private_key_path = "~/.oci/oci_api_key.pem"
  compartment_ocid = "ocid1.compartment.oc1.."
  region           = "us-ashburn-1"

  # Security Configuration - USE YOUR ACTUAL IP!
  allowed_ssh_cidr      = "203.0.113.0/24"  # Your IP
  allowed_api_cidr      = "203.0.113.0/24"  # Your IP
  allowed_nodeport_cidr = "203.0.113.0/24"  # Your IP

  # Instance Configuration
  instance_shape     = "VM.Standard.A1.Flex"
  instance_ocpus     = 2
  instance_memory_gb = 12
  worker_count       = 2
  worker_ocpus       = 1
  worker_memory_gb   = 6

  test_type = "benchmark"
  ```

- [ ] Create `.env` file for local development
  ```bash
  DATABASE_URL=postgresql://benchmark:secure_password@localhost:5432/service_mesh_benchmark
  REDIS_URL=redis://localhost:6379/0
  REDIS_ENABLED=true
  ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8000
  DEBUG=false
  ```

### 3. Verify Free Tier Limits

```bash
# Check current resource usage in OCI
oci limits resource-availability get --compartment-id <compartment-ocid> \
  --service-name compute \
  --limit-name vm-standard-a1-memory-count

# Ensure you're within:
# - 4 OCPUs (ARM)
# - 24GB RAM
# - 200GB block storage
# - 10TB network/month
```

---

## Infrastructure Deployment

### Step 1: Initialize Terraform

```bash
cd terraform/oracle-cloud

# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Plan deployment (review carefully!)
terraform plan -out=tfplan

# Check cost estimate (should be $0 for free tier)
terraform show -json tfplan | jq '.planned_values'
```

### Step 2: Deploy Infrastructure

```bash
# Apply the plan
terraform apply tfplan

# Wait for completion (15-20 minutes)
# Save outputs
terraform output -json > outputs.json

# Get master node IP
MASTER_IP=$(terraform output -raw master_public_ip)
echo "Master Node: $MASTER_IP"
```

### Step 3: Verify Infrastructure

```bash
# SSH into master node
ssh -i ~/.ssh/oci_benchmark_key ubuntu@$MASTER_IP

# Check Kubernetes
kubectl get nodes
# Expected: 1 master + 2 workers, all Ready

# Check system resources
free -h
df -h

# Exit
exit
```

---

## Database Setup

### Step 1: Deploy PostgreSQL to Kubernetes

```bash
# From your local machine
export KUBECONFIG=~/.kube/config-benchmark

# Create benchmark-system namespace and deploy PostgreSQL
kubectl apply -f kubernetes/database/postgres-statefulset.yaml

# Wait for PostgreSQL to be ready
kubectl wait --for=condition=ready pod/postgres-0 -n benchmark-system --timeout=5m

# Verify deployment
kubectl get all -n benchmark-system
```

### Step 2: Initialize Database

```bash
# Get the PostgreSQL password from secret
PG_PASSWORD=$(kubectl get secret postgres-secret -n benchmark-system -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)

# Port-forward to access PostgreSQL
kubectl port-forward -n benchmark-system svc/postgres-service 5432:5432 &

# Connect and verify
psql "postgresql://benchmark:$PG_PASSWORD@localhost:5432/service_mesh_benchmark" -c "\l"

# Run initialization script
psql "postgresql://benchmark:$PG_PASSWORD@localhost:5432/service_mesh_benchmark" -f scripts/init-db.sql

# Kill port-forward
kill %1
```

### Step 3: Create Initial Backup

```bash
# Create backup
kubectl exec -n benchmark-system postgres-0 -- \
  pg_dump -U benchmark service_mesh_benchmark > backup-initial-$(date +%Y%m%d).sql

# Upload to OCI Object Storage (if configured)
oci os object put \
  --bucket-name benchmark-backups \
  --name backup-initial-$(date +%Y%m%d).sql \
  --file backup-initial-$(date +%Y%m%d).sql
```

---

## Application Deployment

### Step 1: Pull Docker Images

```bash
# Login to GitHub Container Registry
echo $GITHUB_TOKEN | docker login ghcr.io -u $GITHUB_USER --password-stdin

# Pull images
docker pull ghcr.io/your-org/service-mesh-benchmark/api:latest
docker pull ghcr.io/your-org/service-mesh-benchmark/ml-workload:latest
docker pull ghcr.io/your-org/service-mesh-benchmark/health-check:latest
```

### Step 2: Deploy API Application

```bash
# Create deployment manifest
kubectl create deployment benchmark-api \
  --image=ghcr.io/your-org/service-mesh-benchmark/api:latest \
  --namespace=benchmark-system \
  --dry-run=client -o yaml > /tmp/api-deployment.yaml

# Add environment variables and resource limits
cat >> /tmp/api-deployment.yaml <<EOF
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: DATABASE_URL
        - name: REDIS_URL
          value: "redis://redis-service:6379/0"
        - name: REDIS_ENABLED
          value: "true"
        resources:
          requests:
            cpu: 250m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi
EOF

# Apply deployment
kubectl apply -f /tmp/api-deployment.yaml

# Create service
kubectl expose deployment benchmark-api \
  --port=8000 \
  --target-port=8000 \
  --type=LoadBalancer \
  --namespace=benchmark-system

# Wait for deployment
kubectl rollout status deployment/benchmark-api -n benchmark-system --timeout=5m
```

### Step 3: Verify API is Running

```bash
# Get API URL
API_URL=$(kubectl get svc benchmark-api -n benchmark-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Test health endpoint
curl http://$API_URL:8000/health

# Test Kubernetes integration
curl http://$API_URL:8000/health/kubernetes

# View API documentation
echo "API Docs: http://$API_URL:8000/docs"
```

---

## Monitoring Setup

### Step 1: Deploy Prometheus

```bash
# Using Helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.retention=30d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=20Gi \
  --set grafana.adminPassword=admin123 \
  --wait

# Verify installation
kubectl get pods -n monitoring
```

### Step 2: Configure Prometheus for Service Mesh

```bash
# Apply custom Prometheus configuration
kubectl create configmap prometheus-config \
  --from-file=monitoring/prometheus/prometheus.yml \
  --namespace=monitoring \
  --dry-run=client -o yaml | kubectl apply -f -

# Reload Prometheus
kubectl rollout restart statefulset/prometheus-prometheus -n monitoring
```

### Step 3: Access Dashboards

```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Open browser to http://localhost:3000
# Login: admin / admin123

# Port-forward Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Open browser to http://localhost:9090
```

---

## Service Mesh Installation

### Option A: Install Istio

```bash
# Using Ansible
cd ansible
ansible-playbook -i inventory/hosts.ini playbooks/setup-istio.yml

# Verify installation
kubectl get pods -n istio-system

# Label namespace for auto-injection
kubectl label namespace default istio-injection=enabled
```

### Option B: Install Cilium

```bash
# Using Ansible
cd ansible
ansible-playbook -i inventory/hosts.ini playbooks/setup-cilium.yml

# Verify installation
kubectl get pods -n kube-system -l k8s-app=cilium

# Check Cilium status
cilium status
```

### Option C: Install Consul

```bash
# Using Ansible
cd ansible
ansible-playbook -i inventory/hosts.ini playbooks/setup-consul.yml

# Verify installation
kubectl get pods -n consul

# Check Consul members
kubectl exec -n consul consul-server-0 -- consul members
```

---

## Post-Deployment Validation

### Step 1: Run Pre-deployment Tests

```bash
cd tests
pytest -v -m phase1 --tb=short
```

### Step 2: Run Infrastructure Tests

```bash
pytest -v -m phase2 --tb=short
```

### Step 3: Deploy Test Workloads

```bash
# Deploy baseline HTTP workload
kubectl apply -f kubernetes/workloads/baseline-http-service.yaml

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=baseline-http-server -n http-benchmark --timeout=3m

# Run baseline test
cd benchmarks/scripts
bash http-load-test.sh
```

### Step 4: Verify Monitoring

```bash
# Check Prometheus targets
curl http://prometheus:9090/api/v1/targets

# Check if metrics are being collected
curl "http://prometheus:9090/api/v1/query?query=up"
```

---

## Rollback Procedures

### Rollback Application Deployment

```bash
# Rollback to previous deployment
kubectl rollout undo deployment/benchmark-api -n benchmark-system

# Rollback to specific revision
kubectl rollout history deployment/benchmark-api -n benchmark-system
kubectl rollout undo deployment/benchmark-api -n benchmark-system --to-revision=2

# Verify rollback
kubectl rollout status deployment/benchmark-api -n benchmark-system
```

### Rollback Database Changes

```bash
# Stop API to prevent writes
kubectl scale deployment benchmark-api --replicas=0 -n benchmark-system

# Restore from backup
kubectl exec -n benchmark-system postgres-0 -- \
  dropdb -U benchmark service_mesh_benchmark

kubectl exec -n benchmark-system postgres-0 -- \
  createdb -U benchmark service_mesh_benchmark

kubectl cp backup-YYYYMMDD.sql benchmark-system/postgres-0:/tmp/
kubectl exec -n benchmark-system postgres-0 -- \
  psql -U benchmark service_mesh_benchmark < /tmp/backup-YYYYMMDD.sql

# Restart API
kubectl scale deployment benchmark-api --replicas=3 -n benchmark-system
```

### Rollback Infrastructure (Nuclear Option)

```bash
cd terraform/oracle-cloud

# Destroy infrastructure
terraform destroy -auto-approve

# Wait 5-10 minutes for complete cleanup

# Re-deploy from scratch
terraform apply -auto-approve
```

---

## Troubleshooting

### API Not Responding

```bash
# Check pod status
kubectl get pods -n benchmark-system -l app=benchmark-api

# View logs
kubectl logs -n benchmark-system -l app=benchmark-api --tail=100 -f

# Check events
kubectl describe pod -n benchmark-system -l app=benchmark-api

# Common issues:
# 1. Database connection failure - check DATABASE_URL secret
# 2. Image pull failure - check GitHub token
# 3. Resource limits - check node resources
```

### Database Connection Issues

```bash
# Check PostgreSQL pod
kubectl get pod postgres-0 -n benchmark-system

# View PostgreSQL logs
kubectl logs postgres-0 -n benchmark-system --tail=50

# Test connection from API pod
kubectl exec -n benchmark-system -it deployment/benchmark-api -- \
  psql "$DATABASE_URL" -c "SELECT 1;"

# Check network policies
kubectl get networkpolicies -n benchmark-system
```

### Service Mesh Not Working

```bash
# Check sidecar injection
kubectl get pod <pod-name> -o jsonpath='{.spec.containers[*].name}'
# Should show both app container and sidecar

# View sidecar logs
kubectl logs <pod-name> -c istio-proxy  # For Istio
kubectl logs <pod-name> -c cilium       # For Cilium
kubectl logs <pod-name> -c consul-sidecar  # For Consul

# Check mesh status
istioctl version          # Istio
cilium status             # Cilium
consul-k8s status         # Consul
```

### Node Resource Exhaustion

```bash
# Check node resources
kubectl top nodes
kubectl describe nodes

# Check pod resource usage
kubectl top pods -A

# Scale down non-essential workloads
kubectl scale deployment <deployment> --replicas=1 -n <namespace>

# Consider upgrading instance size (will exceed free tier)
```

---

## Maintenance Procedures

### Daily Tasks

```bash
# Check cluster health
kubectl get nodes
kubectl get pods -A | grep -v Running

# Check API health
curl http://$API_URL:8000/health

# View recent logs
kubectl logs -n benchmark-system -l app=benchmark-api --since=1h --tail=50
```

### Weekly Tasks

```bash
# Database backup
kubectl exec -n benchmark-system postgres-0 -- \
  pg_dump -U benchmark service_mesh_benchmark | \
  gzip > backup-$(date +%Y%m%d).sql.gz

# Upload to OCI Object Storage
oci os object put \
  --bucket-name benchmark-backups \
  --name backup-$(date +%Y%m%d).sql.gz \
  --file backup-$(date +%Y%m%d).sql.gz

# Clean up old completed jobs
kubectl delete jobs -n default --field-selector status.successful=1

# Update container images
kubectl set image deployment/benchmark-api \
  api=ghcr.io/your-org/service-mesh-benchmark/api:latest \
  -n benchmark-system
```

### Monthly Tasks

```bash
# Update Kubernetes components
sudo apt update && sudo apt upgrade -y

# Update Helm charts
helm repo update
helm upgrade prometheus prometheus-community/kube-prometheus-stack -n monitoring

# Review and clean up old data
psql "$DATABASE_URL" -c "DELETE FROM benchmark_jobs WHERE completed_at < NOW() - INTERVAL '30 days';"

# Review resource utilization and costs
oci usage-api usage summarized-usage list --time-usage-started ...
```

### Quarterly Tasks

```bash
# Full security audit
./scripts/security-audit.sh

# Update all dependencies
pip list --outdated
npm outdated

# Review and update terraform modules
terraform init -upgrade
terraform plan

# Disaster recovery test
# 1. Take full backup
# 2. Deploy to test environment
# 3. Restore from backup
# 4. Verify functionality
```

---

## Emergency Contacts

- **Infrastructure Team**: infra@example.com
- **Database Team**: dba@example.com
- **On-Call Engineer**: +1-555-0123
- **Oracle Cloud Support**: https://cloud.oracle.com/support

---

## Useful Commands Reference

```bash
# Quick health check
kubectl get nodes && kubectl get pods -A | grep -v Running && curl http://$API_URL:8000/health

# View all resources
kubectl get all -A

# Restart all benchmark components
kubectl rollout restart deployment -n benchmark-system

# Emergency scale down
kubectl scale deployment --all --replicas=0 -n benchmark-system

# View resource usage
kubectl top nodes && kubectl top pods -A

# Collect logs for support
kubectl logs -n benchmark-system -l app=benchmark-api --since=1h > api-logs.txt
kubectl describe nodes > nodes-info.txt
kubectl get events -A > events.txt
```

---

**Document Version**: 1.0.0
**Last Reviewed**: 2024-10-27
**Next Review**: 2025-01-27
