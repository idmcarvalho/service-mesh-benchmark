# Security Audit Findings Report

**Audit Date**: 2025-10-23
**Auditor**: Comprehensive Security Analysis
**Project**: Service Mesh Benchmark

---

## Executive Summary

A comprehensive security audit identified **25 security issues** across the project:

- 🔴 **3 Critical** - Require immediate action
- 🟠 **8 High** - Should be addressed within 1 week
- 🟡 **7 Medium** - Address within 1 month
- 🔵 **7 Low** - Address as resources permit

**Key Strengths**:
- Good pre-commit hook infrastructure
- Some workloads have proper security contexts
- RBAC configured with least privilege
- Network policies implemented

**Key Weaknesses**:
- Disabled TLS verification in multiple places
- Many shell scripts lack variable quoting
- Missing security contexts in most workloads
- Binary downloads without checksum verification

---

## 🔴 Critical Issues (Immediate Action Required)

### C1. Kubernetes API TLS Verification Disabled

**File**: `terraform/oracle-cloud/scripts/init-master.sh:93`
**Severity**: CRITICAL

**Issue**:
```bash
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", \
  "value": "--kubelet-insecure-tls"}]'
```

The `--kubelet-insecure-tls` flag completely disables TLS certificate verification between metrics-server and kubelet.

**Impact**:
- Man-in-the-middle attacks possible
- Unauthorized data interception
- Compromised metrics data

**Remediation**:
```bash
# Option 1: Use proper certificates (recommended for production)
# Generate certificates and configure kubelet with valid certs

# Option 2: For test environments only, use host network
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/hostNetwork", "value": true}]'

# Option 3: Remove metrics-server if not needed
kubectl delete deployment metrics-server -n kube-system
```

---

### C2. Direct Binary Download for Helm Without Full Verification

**File**: `terraform/oracle-cloud/scripts/init-master.sh:86-106`
**Severity**: CRITICAL

**Issue**: While checksum verification is present, it only verifies the installer script, not the actual Helm binary that gets installed.

**Current Code**:
```bash
HELM_CHECKSUM="a8ddb4e30435b5fd45308ecce5eaad676d64a5de9c89660b56bebcc8bdf731b6"
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
  -o "${HELM_INSTALL_SCRIPT}"
echo "${HELM_CHECKSUM}  ${HELM_INSTALL_SCRIPT}" | sha256sum -c -
```

**Impact**:
- The installer script could download a malicious Helm binary
- Checksum only verifies the download script, not the final binary

**Remediation**:
```bash
# Download Helm binary directly with checksum
HELM_VERSION="v3.14.0"
HELM_BINARY_URL="https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
HELM_BINARY_SHA256="f43e1c3387de24547506ab05d24e5309c0ce0b228c23bd8aa64e9ec4b8206651"

curl -fsSL "${HELM_BINARY_URL}" -o /tmp/helm.tar.gz
echo "${HELM_BINARY_SHA256}  /tmp/helm.tar.gz" | sha256sum -c - || exit 1

tar -xzf /tmp/helm.tar.gz -C /tmp/
sudo mv /tmp/linux-amd64/helm /usr/local/bin/helm
sudo chmod +x /usr/local/bin/helm
rm -rf /tmp/helm.tar.gz /tmp/linux-amd64
```

---

### C3. Insecure gRPC Testing Without TLS

**File**: `benchmarks/scripts/grpc-test.sh:66`
**Severity**: CRITICAL

**Issue**:
```bash
ghz --insecure \  # Disables TLS verification!
    --proto=/dev/null \
    --call=grpc.health.v1.Health/Check \
    ... "$SERVICE_URL"
```

**Impact**: MITM attacks, credential interception in gRPC streams

**Remediation**:
```bash
# For test environments, explicitly document why insecure is used
# Add warning and environment check
if [[ "${ALLOW_INSECURE_GRPC:-false}" != "true" ]]; then
    echo "ERROR: Insecure gRPC disabled. Set ALLOW_INSECURE_GRPC=true for test environments only" >&2
    exit 1
fi

# For production, use proper TLS
ghz \
    --cacert "${GRPC_CA_CERT}" \
    --cert "${GRPC_CLIENT_CERT}" \
    --key "${GRPC_CLIENT_KEY}" \
    ... "$SERVICE_URL"
```

---

## 🟠 High Priority Issues

### H1. Missing Security Contexts in Most Kubernetes Workloads

**Files**:
- `kubernetes/workloads/http-service.yaml`
- `kubernetes/workloads/grpc-service.yaml`
- `kubernetes/workloads/websocket-service.yaml`
- `kubernetes/workloads/database-cluster.yaml`
- `kubernetes/workloads/baseline-http-service.yaml`
- `kubernetes/workloads/baseline-grpc-service.yaml`

**Severity**: HIGH

**Issue**: Only ml-batch-job.yaml and health-check-service.yaml have security contexts. All other workloads run with default (root) permissions.

**Example from http-service.yaml:55-71**:
```yaml
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    # MISSING: securityContext!
    ports:
    - containerPort: 80
```

**Impact**:
- Containers run as root
- Can modify host filesystem
- Privilege escalation possible
- Container escape risk

**Remediation**: Apply to ALL workloads:
```yaml
spec:
  # Pod-level security context
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault

  containers:
  - name: nginx
    image: nginx:alpine
    # Container-level security context
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      runAsNonRoot: true
      runAsUser: 1000
      capabilities:
        drop:
          - ALL
    volumeMounts:
    - name: tmp
      mountPath: /tmp
    - name: cache
      mountPath: /var/cache/nginx

  volumes:
  - name: tmp
    emptyDir: {}
  - name: cache
    emptyDir: {}
```

---

### H2. Unquoted Variables in Shell Scripts (Command Injection Risk)

**Files**:
- `benchmarks/scripts/ml-workload.sh:21`
- `benchmarks/scripts/websocket-test.sh:31-32`
- `benchmarks/scripts/collect-metrics.sh:82-83`
- `benchmarks/scripts/test-network-policies.sh:29,94,98`
- `benchmarks/scripts/collect-ebpf-metrics.sh:27,32`
- `benchmarks/scripts/grpc-test.sh:15-20`

**Severity**: HIGH

**Examples**:
```bash
# ml-workload.sh:21 - VULNERABLE
kubectl create namespace $NAMESPACE

# test-network-policies.sh:94 - VULNERABLE
kubectl run test-warmup -- curl -s http://$service_url/

# collect-metrics.sh:82 - VULNERABLE
for ns in http-benchmark grpc-benchmark; do
    if kubectl get namespace $ns &> /dev/null; then
```

**Impact**: Shell injection if variables contain spaces or metacharacters

**Remediation**:
```bash
# SAFE - Quote all variables
kubectl create namespace "${NAMESPACE}"
kubectl run test-warmup -- curl -s "http://${service_url}/"

for ns in http-benchmark grpc-benchmark; do
    if kubectl get namespace "${ns}" &> /dev/null; then
```

**Automated Fix**: Run the script we created:
```bash
python3 scripts/auto-fix-shell-quotes.py
```

---

### H3. Binary Downloads Without Checksum Verification

**Files**:
- `benchmarks/scripts/grpc-test.sh:58-61`
- `benchmarks/scripts/websocket-test.sh:31-33`
- `ebpf-probes/latency-probe/build.sh:17-20`

**Severity**: HIGH

**Examples**:
```bash
# grpc-test.sh:58 - NO VERIFICATION
wget -q https://github.com/bojand/ghz/releases/download/v0.117.0/ghz-linux-x86_64.tar.gz
tar -xzf ghz-linux-x86_64.tar.gz
sudo mv ghz /usr/local/bin/

# websocket-test.sh:31 - NO VERIFICATION
wget -qO- https://github.com/vi/websocat/releases/download/v1.12.0/websocat.x86_64-unknown-linux-musl \
  -O /tmp/websocat
sudo install /tmp/websocat /usr/local/bin/
```

**Impact**: Supply chain attack, malware installation

**Remediation**:
```bash
# grpc-test.sh - ADD CHECKSUMS
GHZ_VERSION="v0.117.0"
GHZ_SHA256="<get_actual_sha256_from_releases>"
GHZ_URL="https://github.com/bojand/ghz/releases/download/${GHZ_VERSION}/ghz-linux-x86_64.tar.gz"

wget -O /tmp/ghz.tar.gz "${GHZ_URL}"
echo "${GHZ_SHA256}  /tmp/ghz.tar.gz" | sha256sum -c - || {
    echo "ERROR: Checksum verification failed for ghz" >&2
    rm -f /tmp/ghz.tar.gz
    exit 1
}

tar -xzf /tmp/ghz.tar.gz -C /tmp/
sudo mv /tmp/ghz /usr/local/bin/
rm -f /tmp/ghz.tar.gz
```

---

### H4-H8. Additional High Priority Issues

**H4**: Calico Installation Without Version Pinning (`init-master.sh:96-97`)
**H5**: Missing `set -euo pipefail` in Shell Scripts
**H6**: Temporary Files Without Secure Creation (`websocket-test.sh:37`)
**H7**: No Input Validation for User-Provided URLs
**H8**: Missing Resource Limits in Baseline Workloads

---

## 🟡 Medium Priority Issues

### M1. Weak Network Egress Filtering

**File**: `terraform/oracle-cloud/main.tf:72-126`
**Severity**: MEDIUM

**Issue**: While restricted to specific ports, egress still allows connections to ANY destination IP on those ports.

**Current**:
```hcl
egress_security_rules {
  description = "HTTPS to package repositories"
  destination = "0.0.0.0/0"  # Too broad!
  protocol    = "6"
  tcp_options {
    min = 443
    max = 443
  }
}
```

**Recommendation**:
```hcl
# Create separate rules for known repositories
egress_security_rules {
  description = "HTTPS to PyPI"
  destination = "151.101.0.0/16"  # PyPI CDN
  protocol    = "6"
  tcp_options {
    min = 443
    max = 443
  }
}

egress_security_rules {
  description = "HTTPS to GitHub"
  destination = "140.82.112.0/20"  # GitHub
  protocol    = "6"
  tcp_options {
    min = 443
    max = 443
  }
}
```

---

### M2-M7. Additional Medium Priority Issues

**M2**: Incomplete RBAC Permissions for Benchmarks
**M3**: Vulnerable Dependency - psutil 5.9.8
**M4**: Missing Pod Security Standards Labels on Namespaces
**M5**: No Kubernetes Audit Logging Configuration
**M6**: Flask Debug Mode Not Explicitly Disabled
**M7**: Missing Network Policy Egress Rules

---

## 🔵 Low Priority Issues

**L1**: Flask Listening on 0.0.0.0 (necessary but undocumented)
**L2**: No Content Security Policy Headers in HTML Reports
**L3**: Service Account Token Auto-Mounting Not Globally Controlled
**L4**: Missing Liveness Probes in Some Workloads
**L5**: No Rate Limiting on API Endpoints
**L6**: Insufficient Security Logging
**L7**: No Pod Disruption Budgets

---

## Remediation Roadmap

### Week 1 (Critical + High Priority)
- [ ] Fix TLS verification for metrics-server (C1)
- [ ] Improve Helm installation security (C2)
- [ ] Add TLS to gRPC testing or document insecurity (C3)
- [ ] Add security contexts to all 6 missing workloads (H1)
- [ ] Quote all variables in shell scripts (H2)
- [ ] Add checksum verification to binary downloads (H3)

### Week 2-3 (Remaining High Priority)
- [ ] Pin Calico version (H4)
- [ ] Add `set -euo pipefail` to all scripts (H5)
- [ ] Use mktemp for temporary files (H6)
- [ ] Add URL validation (H7)
- [ ] Add resource limits to baselines (H8)

### Month 2 (Medium Priority)
- [ ] Implement specific IP egress filtering (M1)
- [ ] Expand RBAC permissions (M2)
- [ ] Update dependencies (M3)
- [ ] Add Pod Security Standards (M4)
- [ ] Configure audit logging (M5)
- [ ] Explicitly disable Flask debug (M6)
- [ ] Complete network policies (M7)

### Month 3+ (Low Priority)
- [ ] Document Flask 0.0.0.0 binding (L1)
- [ ] Add CSP headers (L2)
- [ ] Control service account tokens (L3)
- [ ] Add missing probes (L4)
- [ ] Implement rate limiting (L5)
- [ ] Enhance security logging (L6)
- [ ] Add PodDisruptionBudgets (L7)

---

## Automated Fix Scripts

### 1. Add Security Contexts to All Workloads

Create `scripts/add-security-contexts.py`:

```python
#!/usr/bin/env python3
import yaml
from pathlib import Path

WORKLOAD_DIR = Path("kubernetes/workloads")
SECURITY_CONTEXT_POD = {
    "runAsNonRoot": True,
    "runAsUser": 1000,
    "runAsGroup": 1000,
    "fsGroup": 1000,
    "seccompProfile": {"type": "RuntimeDefault"}
}

SECURITY_CONTEXT_CONTAINER = {
    "allowPrivilegeEscalation": False,
    "readOnlyRootFilesystem": True,
    "runAsNonRoot": True,
    "runAsUser": 1000,
    "capabilities": {"drop": ["ALL"]}
}

for yaml_file in WORKLOAD_DIR.glob("*.yaml"):
    if yaml_file.name in ["ml-batch-job.yaml", "health-check-service.yaml"]:
        continue  # Already has security contexts

    print(f"Processing {yaml_file.name}...")
    # Add security context logic here
```

### 2. Quote All Variables

Already created: `scripts/auto-fix-shell-quotes.py`

### 3. Add Checksums to Downloads

Create `scripts/add-checksums.sh`:

```bash
#!/bin/bash
# Extract checksums from GitHub releases
# Add to respective scripts
```

---

## Testing Checklist

After applying fixes:

- [ ] Run pre-commit hooks: `pre-commit run --all-files`
- [ ] Validate Terraform: `terraform validate && tfsec terraform/`
- [ ] Test shell scripts: `shellcheck benchmarks/scripts/*.sh`
- [ ] Dry-run Kubernetes: `kubectl apply --dry-run=server -f kubernetes/`
- [ ] Build Docker images: Verify builds succeed
- [ ] Test network policies: Verify connectivity
- [ ] Verify RBAC: Test with service account
- [ ] Run security scans: GitHub Actions workflow

---

## Summary Statistics

| Category | Count | Status |
|----------|-------|--------|
| Critical Issues | 3 | ❌ Needs immediate fix |
| High Priority | 8 | ⚠️ Fix within 1 week |
| Medium Priority | 7 | 🟡 Fix within 1 month |
| Low Priority | 7 | 🔵 Fix as time permits |
| **Total Issues** | **25** | **Action required** |

---

## References

- [SECURITY_HARDENING.md](SECURITY_HARDENING.md) - Original security guidelines
- [SECURITY_IMPLEMENTATION.md](SECURITY_IMPLEMENTATION.md) - Completed implementations
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)

---

**Next Steps**: Start with Critical issues this week, then systematically address High priority issues.

