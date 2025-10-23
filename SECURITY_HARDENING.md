# Security Hardening Guide

## Executive Summary

This document provides comprehensive security hardening guidelines for the Service Mesh Benchmark project. It addresses identified vulnerabilities, code smells, and infrastructure security concerns discovered during security audit.

## Severity Levels

- 🔴 **CRITICAL**: Immediate action required - exploitation could lead to system compromise
- 🟠 **HIGH**: Significant risk - should be addressed within 1 week
- 🟡 **MEDIUM**: Moderate risk - address within 1 month
- 🔵 **LOW**: Minor issue - address as resources permit

---

## 1. Critical Security Issues

### 1.1 🔴 Unsafe Script Execution in Infrastructure

**File**: `terraform/oracle-cloud/scripts/init-master.sh:87`

**Issue**: Piping curl directly to bash without verification
```bash
# VULNERABLE CODE
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

**Risk**: Remote code execution if GitHub is compromised or MITM attack occurs

**Fix**:
```bash
# Download and verify
HELM_VERSION="v3.14.0"
HELM_INSTALL_SCRIPT="/tmp/get-helm-${HELM_VERSION}.sh"
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o "${HELM_INSTALL_SCRIPT}"

# Verify checksum (obtain from official Helm releases)
echo "expected_sha256_here ${HELM_INSTALL_SCRIPT}" | sha256sum -c -

# Execute with restricted permissions
chmod 700 "${HELM_INSTALL_SCRIPT}"
"${HELM_INSTALL_SCRIPT}" --version "${HELM_VERSION}"

# Cleanup
rm -f "${HELM_INSTALL_SCRIPT}"
```

### 1.2 🔴 Dynamic Package Installation in Production Containers

**Files**:
- `kubernetes/workloads/ml-batch-job.yaml:30-52`
- `kubernetes/workloads/health-check-service.yaml:99-101`

**Issue**: Installing packages at runtime without version pinning
```yaml
# VULNERABLE CODE
args:
  - -c
  - |
    pip install numpy scikit-learn pandas
```

**Risk**: Supply chain attack, dependency confusion, unpredictable behavior

**Fix**: Create pre-built container images
```dockerfile
# Dockerfile for ML workload
FROM python:3.11-slim

# Pin all dependencies
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r /app/requirements.txt

# requirements.txt with pinned versions
# numpy==1.26.2
# scikit-learn==1.3.2
# pandas==2.1.4

COPY app.py /app/
WORKDIR /app

USER 1000:1000
CMD ["python", "app.py"]
```

### 1.3 🔴 Unrestricted Network Egress

**File**: `terraform/oracle-cloud/main.tf:72-75`

**Issue**: Security group allows all outbound traffic
```hcl
egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
}
```

**Risk**: Data exfiltration, command and control communication

**Fix**:
```hcl
# Allow only necessary egress
egress_security_rules {
    description = "HTTPS to package repositories"
    destination = "0.0.0.0/0"  # Better: restrict to specific repos
    protocol    = "6"  # TCP
    tcp_options {
        min = 443
        max = 443
    }
}

egress_security_rules {
    description = "DNS"
    destination = "0.0.0.0/0"
    protocol    = "17"  # UDP
    udp_options {
        min = 53
        max = 53
    }
}

egress_security_rules {
    description = "NTP"
    destination = "0.0.0.0/0"
    protocol    = "17"  # UDP
    udp_options {
        min = 123
        max = 123
    }
}
```

---

## 2. High Priority Issues

### 2.1 🟠 Shell Injection Vulnerabilities

**Files**: Multiple shell scripts in `benchmarks/scripts/`

**Issue**: Unquoted variables in shell commands
```bash
# VULNERABLE
kubectl run test -n $NAMESPACE -- curl http://$SERVICE_URL/
```

**Risk**: Command injection if variables contain shell metacharacters

**Fix**:
```bash
# SAFE - Always quote variables
kubectl run test -n "${NAMESPACE}" -- curl "http://${SERVICE_URL}/"

# Even better - validate inputs
if [[ ! "${NAMESPACE}" =~ ^[a-z0-9-]+$ ]]; then
    echo "Error: Invalid namespace format" >&2
    exit 1
fi
```

**Automated Fix Script**:
```bash
#!/bin/bash
# fix-shell-injection.sh - Quote all variables in shell scripts

set -euo pipefail

for script in benchmarks/scripts/*.sh; do
    echo "Hardening: ${script}"

    # Backup original
    cp "${script}" "${script}.backup"

    # Add shellcheck directive
    sed -i '1a # shellcheck shell=bash' "${script}"

    # Run shellcheck and fix automatically where possible
    shellcheck -f diff "${script}" | patch "${script}" || true
done
```

### 2.2 🟠 Missing Security Contexts in Kubernetes

**Files**: All workload manifests in `kubernetes/workloads/`

**Issue**: Containers run as root without security restrictions

**Risk**: Container escape, privilege escalation

**Fix Template**:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
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
  - name: app
    image: myapp:1.0

    # Container-level security context
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      runAsNonRoot: true
      runAsUser: 1000
      capabilities:
        drop:
          - ALL
        # add: ["NET_BIND_SERVICE"]  # If needed

    # Volume for writable directories
    volumeMounts:
    - name: tmp
      mountPath: /tmp
    - name: cache
      mountPath: /app/cache

  volumes:
  - name: tmp
    emptyDir: {}
  - name: cache
    emptyDir: {}
```

**Automated Fix Script**:
```bash
#!/bin/bash
# add-security-contexts.sh

set -euo pipefail

SECURITY_CONTEXT='
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault'

CONTAINER_SECURITY='
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        runAsNonRoot: true
        runAsUser: 1000
        capabilities:
          drop:
            - ALL'

for manifest in kubernetes/workloads/*.yaml; do
    echo "Hardening: ${manifest}"

    # Backup
    cp "${manifest}" "${manifest}.backup"

    # Add pod security context after spec:
    sed -i '/^spec:$/a\'"${SECURITY_CONTEXT}" "${manifest}"

    # Add container security context after containers:
    sed -i '/^  - name:/a\'"${CONTAINER_SECURITY}" "${manifest}"
done
```

### 2.3 🟠 Dangerous Terraform Defaults

**File**: `terraform/oracle-cloud/variables.tf:46,56,66`

**Issue**: Default CIDR is `0.0.0.0/0` with only a comment warning

**Risk**: Accidental exposure to entire internet

**Fix**:
```hcl
# BEFORE (DANGEROUS)
variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH"
  type        = string
  default     = "0.0.0.0/0"  # Change this!
}

# AFTER (SAFE)
variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH (e.g., 203.0.113.0/24)"
  type        = string
  # NO DEFAULT - force user to specify

  validation {
    condition     = can(cidrhost(var.allowed_ssh_cidr, 0))
    error_message = "Must be a valid CIDR block (e.g., 203.0.113.0/24)"
  }

  validation {
    condition     = var.allowed_ssh_cidr != "0.0.0.0/0"
    error_message = "Cannot use 0.0.0.0/0 - specify your actual IP range"
  }
}
```

### 2.4 🟠 Insufficient Input Validation

**File**: `tests/conftest.py:69-70`

**Issue**: Integer conversion without validation
```python
# VULNERABLE
test_duration=int(request.config.getoption("--test-duration")),
```

**Risk**: ValueError crash, negative values, resource exhaustion

**Fix**:
```python
def validate_positive_int(value: str, name: str, min_val: int = 1, max_val: int = 86400) -> int:
    """Validate and convert string to positive integer within bounds."""
    try:
        int_val = int(value)
    except ValueError as e:
        raise ValueError(f"{name} must be an integer, got: {value}") from e

    if int_val < min_val:
        raise ValueError(f"{name} must be >= {min_val}, got: {int_val}")

    if int_val > max_val:
        raise ValueError(f"{name} must be <= {max_val}, got: {int_val}")

    return int_val

# Usage
test_duration = validate_positive_int(
    request.config.getoption("--test-duration"),
    "test-duration",
    min_val=1,
    max_val=3600
)
```

---

## 3. Medium Priority Issues

### 3.1 🟡 Binary Download Without Verification

**Files**: Multiple Ansible playbooks and shell scripts

**Issue**: Downloading binaries without checksum verification

**Fix Pattern**:
```yaml
# Ansible playbook pattern
- name: Download Helm binary
  get_url:
    url: "https://get.helm.sh/helm-v3.14.0-linux-amd64.tar.gz"
    dest: "/tmp/helm.tar.gz"
    checksum: "sha256:f43e1c3387de24547506ab05d24e5309c0ce0b228c23bd8aa64e9ec4b8206651"
    mode: '0644'
  register: helm_download

- name: Verify download succeeded
  assert:
    that:
      - helm_download is succeeded
    fail_msg: "Failed to download Helm binary"
```

### 3.2 🟡 Bare Exception Handling

**File**: `tests/test_phase2_infrastructure.py:165-166`

**Issue**: Catching all exceptions including system exits
```python
# VULNERABLE
try:
    cleanup()
except:
    pass
```

**Fix**:
```python
# SAFE
import logging

logger = logging.getLogger(__name__)

try:
    cleanup()
except (ApiException, ValueError) as e:
    logger.warning(f"Cleanup failed: {type(e).__name__}: {e}")
except Exception as e:
    logger.error(f"Unexpected cleanup error: {type(e).__name__}: {e}", exc_info=True)
    # Re-raise if critical
    if isinstance(e, KeyboardInterrupt):
        raise
```

### 3.3 🟡 Test Resource Cleanup

**Issue**: Tests create resources but don't guarantee cleanup

**Fix**: Use pytest fixtures with proper teardown
```python
import pytest
from contextlib import contextmanager

@contextmanager
def temporary_namespace(k8s_client, name: str):
    """Context manager for temporary namespace with guaranteed cleanup."""
    namespace = client.V1Namespace(
        metadata=client.V1ObjectMeta(name=name)
    )

    try:
        k8s_client["core"].create_namespace(namespace)
        yield name
    finally:
        try:
            k8s_client["core"].delete_namespace(
                name=name,
                body=client.V1DeleteOptions(
                    propagation_policy='Foreground'
                )
            )
            # Wait for deletion
            import time
            timeout = 60
            start = time.time()
            while time.time() - start < timeout:
                try:
                    k8s_client["core"].read_namespace(name)
                    time.sleep(1)
                except ApiException as e:
                    if e.status == 404:
                        break
        except Exception as e:
            pytest.fail(f"Failed to cleanup namespace {name}: {e}")

# Usage in tests
def test_namespace_operations(k8s_client):
    with temporary_namespace(k8s_client, "test-ns") as ns:
        # Test code here
        assert ns == "test-ns"
    # Namespace automatically cleaned up
```

---

## 4. Infrastructure Hardening

### 4.1 Kubernetes RBAC

Create least-privilege service accounts:

```yaml
# rbac/benchmark-sa.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: benchmark-runner
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: benchmark-runner
  namespace: default
rules:
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: benchmark-runner
  namespace: default
subjects:
- kind: ServiceAccount
  name: benchmark-runner
  namespace: default
roleRef:
  kind: Role
  name: benchmark-runner
  apiGroup: rbac.authorization.k8s.io
```

### 4.2 Network Policies

Restrict pod-to-pod communication:

```yaml
# policies/default-deny.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
# policies/allow-benchmark.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-http-benchmark
  namespace: http-benchmark
spec:
  podSelector:
    matchLabels:
      app: http-server
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: http-client
    ports:
    - protocol: TCP
      port: 80
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: http-server
    ports:
    - protocol: TCP
      port: 80
  # DNS
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

### 4.3 Pod Security Standards

Enable PSS at cluster level:

```yaml
# Apply to namespaces
apiVersion: v1
kind: Namespace
metadata:
  name: http-benchmark
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### 4.4 Secret Management

Use Kubernetes secrets properly:

```bash
# Create secrets from files (not inline)
kubectl create secret generic benchmark-config \
  --from-file=config.yaml \
  --dry-run=client -o yaml | kubectl apply -f -

# Use sealed-secrets for GitOps
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# Seal secret
kubeseal --format=yaml < secret.yaml > sealed-secret.yaml
```

---

## 5. CI/CD Security

### 5.1 GitHub Actions Security

```yaml
# .github/workflows/security-scan.yml
name: Security Scan

on:
  pull_request:
  push:
    branches: [main]
  schedule:
    - cron: '0 0 * * 0'  # Weekly

jobs:
  security-scan:
    runs-on: ubuntu-latest

    permissions:
      contents: read
      security-events: write

    steps:
    - uses: actions/checkout@v4

    - name: Run Trivy vulnerability scanner
      uses: aquasecurity/trivy-action@master
      with:
        scan-type: 'fs'
        scan-ref: '.'
        format: 'sarif'
        output: 'trivy-results.sarif'

    - name: Upload Trivy results to GitHub Security
      uses: github/codeql-action/upload-sarif@v2
      with:
        sarif_file: 'trivy-results.sarif'

    - name: Run Checkov
      uses: bridgecrewio/checkov-action@master
      with:
        directory: terraform/
        framework: terraform
        output_format: sarif
        output_file_path: checkov-results.sarif

    - name: Shellcheck
      run: |
        find . -name "*.sh" -exec shellcheck {} \;

    - name: Bandit (Python security)
      run: |
        pip install bandit[toml]
        bandit -r tests/ -f json -o bandit-results.json
```

### 5.2 Pre-commit Hooks

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: check-yaml
      - id: check-json
      - id: check-added-large-files
      - id: detect-private-key
      - id: end-of-file-fixer
      - id: trailing-whitespace

  - repo: https://github.com/koalaman/shellcheck-precommit
    rev: v0.9.0
    hooks:
      - id: shellcheck

  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.86.0
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_tfsec

  - repo: https://github.com/PyCQA/bandit
    rev: 1.7.5
    hooks:
      - id: bandit
        args: ['-c', 'pyproject.toml']

  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.1.9
    hooks:
      - id: ruff
        args: [--fix, --exit-non-zero-on-fix]
```

---

## 6. Monitoring & Alerting

### 6.1 Audit Logging

Enable Kubernetes audit logging:

```yaml
# audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # Log secret access
  - level: RequestResponse
    verbs: ["get", "list", "watch"]
    resources:
      - group: ""
        resources: ["secrets"]

  # Log authentication attempts
  - level: Metadata
    verbs: ["create", "update", "patch", "delete"]
    resources:
      - group: "authentication.k8s.io"

  # Log RBAC changes
  - level: RequestResponse
    verbs: ["create", "update", "patch", "delete"]
    resources:
      - group: "rbac.authorization.k8s.io"
```

### 6.2 Runtime Security

Deploy Falco for runtime security:

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm install falco falcosecurity/falco \
  --namespace falco --create-namespace \
  --set falco.grpc.enabled=true \
  --set falco.grpcOutput.enabled=true
```

---

## 7. Compliance Checklist

### Pre-Deployment

- [ ] All Terraform variables validated
- [ ] No default `0.0.0.0/0` CIDR blocks
- [ ] SSH keys rotated and permissions set to 0600
- [ ] Secrets not in version control
- [ ] All container images scanned for vulnerabilities
- [ ] Security contexts applied to all pods
- [ ] Network policies defined

### Post-Deployment

- [ ] RBAC configured with least privilege
- [ ] Audit logging enabled
- [ ] Runtime security monitoring active
- [ ] Backup strategy implemented
- [ ] Incident response plan documented
- [ ] Security training completed

### Regular Maintenance

- [ ] Weekly vulnerability scans
- [ ] Monthly access reviews
- [ ] Quarterly penetration testing
- [ ] Annual security audit

---

## 8. Quick Wins

Immediate actions that can be taken today:

```bash
# 1. Add shellcheck to all scripts
for script in benchmarks/scripts/*.sh; do
    sed -i '1a # shellcheck shell=bash' "$script"
done

# 2. Quote all variables
# Run shellcheck and fix warnings
find . -name "*.sh" -exec shellcheck --format=diff {} \; | patch

# 3. Add input validation to Python
pip install pydantic
# Use Pydantic models for config validation

# 4. Enable Terraform validation
cd terraform/oracle-cloud
terraform validate
tfsec .

# 5. Install pre-commit hooks
pre-commit install
pre-commit run --all-files
```

---

## References

- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [OWASP Kubernetes Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Kubernetes_Security_Cheat_Sheet.html)
- [NSA Kubernetes Hardening Guidance](https://media.defense.gov/2022/Aug/29/2003066362/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.2_20220829.PDF)
- [Terraform Security Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)

