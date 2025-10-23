# Security Quick Start Guide

Quick reference for using the security measures in this project.

## Before You Start

### 1. Install Security Tools

```bash
# Install pre-commit hooks
pip install pre-commit
pre-commit install

# Install shellcheck (Linux/macOS)
sudo apt-get install shellcheck  # Ubuntu/Debian
brew install shellcheck          # macOS

# Install Terraform security tools
brew install tfsec
pip install checkov
```

### 2. Configure Terraform Securely

```bash
cd terraform/oracle-cloud

# Copy and edit the example file
cp terraform.tfvars.example terraform.tfvars

# IMPORTANT: Get your IP address
curl ifconfig.me

# Edit terraform.tfvars and replace YOUR.IP.ADDRESS.HERE with your actual IP
# Example: allowed_ssh_cidr = "203.0.113.42/32"
vim terraform.tfvars

# Validate your configuration
terraform validate

# Run security scan
tfsec .
```

### 3. Build Secure Docker Images

```bash
# Build ML workload image
docker build -t ml-workload:v1.0.0 \
  -f docker/ml-workload/Dockerfile \
  docker/ml-workload/

# Build ML inference image
docker build -t ml-inference:v1.0.0 \
  -f docker/ml-workload/Dockerfile.inference \
  docker/ml-workload/

# Build health-check image
docker build -t health-check:v1.0.0 \
  -f docker/health-check/Dockerfile \
  docker/health-check/

# Scan images for vulnerabilities
docker scan ml-workload:v1.0.0
docker scan health-check:v1.0.0
```

## Running Security Checks

### Pre-commit Checks

```bash
# Run all checks on staged files
pre-commit run

# Run all checks on all files
pre-commit run --all-files

# Run specific check
pre-commit run bandit --all-files
pre-commit run shellcheck --all-files
```

### Manual Security Scans

```bash
# Python security scan
bandit -r tests/ -ll

# Shell script validation
find benchmarks/scripts -name "*.sh" -exec shellcheck {} \;

# Terraform security
cd terraform/oracle-cloud
tfsec .
checkov -d .

# Docker image scanning
trivy image ml-workload:v1.0.0
trivy image health-check:v1.0.0

# Secret detection
detect-secrets scan
```

## Deploying Securely

### 1. Apply RBAC First

```bash
# Create service accounts and roles
kubectl apply -f kubernetes/rbac/

# Verify RBAC
kubectl get serviceaccounts
kubectl get roles
kubectl get rolebindings
```

### 2. Apply Network Policies

```bash
# Apply default deny policy
kubectl apply -f kubernetes/network-policies/default-deny.yaml

# Apply specific allow policies
kubectl apply -f kubernetes/network-policies/allow-http-benchmark.yaml
kubectl apply -f kubernetes/network-policies/allow-grpc-benchmark.yaml
kubectl apply -f kubernetes/network-policies/allow-dns-egress.yaml

# Verify network policies
kubectl get networkpolicies -A
```

### 3. Deploy Workloads

```bash
# Deploy with security contexts
kubectl apply -f kubernetes/workloads/ml-batch-job.yaml
kubectl apply -f kubernetes/workloads/health-check-service.yaml

# Verify security contexts
kubectl get pod <pod-name> -o jsonpath='{.spec.securityContext}'
kubectl get pod <pod-name> -o jsonpath='{.spec.containers[0].securityContext}'
```

## Troubleshooting

### Common Issues

**Issue**: Terraform validation fails with CIDR error
```
Error: Cannot use 0.0.0.0/0 - specify your actual IP range
```
**Solution**: Get your IP with `curl ifconfig.me` and use it in terraform.tfvars with /32 suffix.

---

**Issue**: Docker build fails with permission error
```
Error: cannot create /app: Permission denied
```
**Solution**: Check that Dockerfile has proper chown commands for non-root user.

---

**Issue**: Pod fails to start with security context error
```
Error: container has runAsNonRoot and image has non-numeric user
```
**Solution**: Verify Dockerfile creates user with numeric UID (1000).

---

**Issue**: Network policy blocks legitimate traffic
```
Error: Connection refused or timeout
```
**Solution**: Check NetworkPolicy ingress/egress rules match pod labels and ports.

---

**Issue**: Pre-commit hook fails
```
Error: [ERROR] Tool not found
```
**Solution**: Install missing tool: `pip install <tool>` or `brew install <tool>`

## Quick Commands Reference

```bash
# Security scan everything
pre-commit run --all-files && \
  tfsec terraform/oracle-cloud && \
  bandit -r tests/ && \
  shellcheck benchmarks/scripts/*.sh

# Build all Docker images
for dir in docker/*/; do
  name=$(basename "$dir")
  docker build -t "$name:v1.0.0" -f "$dir/Dockerfile" "$dir"
done

# Apply all Kubernetes security configs
kubectl apply -f kubernetes/rbac/
kubectl apply -f kubernetes/network-policies/

# Check pod security
kubectl get pods -o custom-columns=\
NAME:.metadata.name,\
USER:.spec.securityContext.runAsUser,\
NONROOT:.spec.securityContext.runAsNonRoot

# View security contexts
kubectl get pods -o json | \
  jq '.items[] | {name:.metadata.name, securityContext:.spec.securityContext}'
```

## Security Checklist

Before committing code:
- [ ] Run `pre-commit run --all-files`
- [ ] No secrets in code
- [ ] All shell variables quoted
- [ ] Terraform CIDR blocks not 0.0.0.0/0

Before deploying:
- [ ] Docker images built and scanned
- [ ] RBAC applied
- [ ] Network policies applied
- [ ] Security contexts in all pods
- [ ] Non-root user in all containers

After deploying:
- [ ] Test connectivity with network policies
- [ ] Verify pods running as non-root
- [ ] Check security logs
- [ ] Review GitHub Security tab

## Getting Help

- **Security Hardening Guide**: See [SECURITY_HARDENING.md](SECURITY_HARDENING.md)
- **Implementation Details**: See [SECURITY_IMPLEMENTATION.md](SECURITY_IMPLEMENTATION.md)
- **Report Security Issues**: security@example.com (Do NOT use GitHub issues)

---

**Last Updated**: 2025-10-21
