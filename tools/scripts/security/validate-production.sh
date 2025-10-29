#!/bin/bash
# Production Readiness Validation Script
# Validates that all production components are properly configured

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0
WARNINGS=0

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Validate prerequisites
validate_prerequisites() {
    print_header "Validating Prerequisites"

    if command_exists kubectl; then
        check_pass "kubectl is installed ($(kubectl version --client --short 2>/dev/null | head -1))"
    else
        check_fail "kubectl is not installed"
    fi

    if command_exists terraform; then
        check_pass "terraform is installed ($(terraform version -json | jq -r '.terraform_version' 2>/dev/null || echo 'unknown'))"
    else
        check_fail "terraform is not installed"
    fi

    if command_exists helm; then
        check_pass "helm is installed ($(helm version --short 2>/dev/null))"
    else
        check_warn "helm is not installed (optional but recommended)"
    fi

    if command_exists ansible; then
        check_pass "ansible is installed"
    else
        check_warn "ansible is not installed (needed for service mesh setup)"
    fi

    if command_exists docker; then
        check_pass "docker is installed ($(docker --version | cut -d' ' -f3 | tr -d ','))"
    else
        check_warn "docker is not installed (needed for local development)"
    fi
}

# Validate Kubernetes cluster
validate_kubernetes() {
    print_header "Validating Kubernetes Cluster"

    if kubectl cluster-info &> /dev/null; then
        check_pass "Kubernetes cluster is accessible"

        # Check nodes
        local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
        if [ "$node_count" -ge 1 ]; then
            check_pass "Found $node_count node(s)"
        else
            check_fail "No nodes found in cluster"
        fi

        # Check node status
        local ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo "0")
        if [ "$ready_nodes" -eq "$node_count" ]; then
            check_pass "All $ready_nodes node(s) are Ready"
        else
            check_fail "Only $ready_nodes/$node_count nodes are Ready"
        fi
    else
        check_fail "Cannot connect to Kubernetes cluster"
        return
    fi
}

# Validate database
validate_database() {
    print_header "Validating Database"

    if kubectl get namespace benchmark-system &> /dev/null; then
        check_pass "benchmark-system namespace exists"
    else
        check_warn "benchmark-system namespace not found (not deployed yet)"
        return
    fi

    if kubectl get statefulset postgres -n benchmark-system &> /dev/null; then
        check_pass "PostgreSQL StatefulSet exists"

        local postgres_ready=$(kubectl get statefulset postgres -n benchmark-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        if [ "$postgres_ready" -ge 1 ]; then
            check_pass "PostgreSQL pod is ready"

            # Test database connection
            if kubectl exec -n benchmark-system postgres-0 -- psql -U benchmark -d service_mesh_benchmark -c "SELECT 1;" &> /dev/null; then
                check_pass "Database connection successful"
            else
                check_fail "Cannot connect to database"
            fi
        else
            check_fail "PostgreSQL pod is not ready"
        fi
    else
        check_warn "PostgreSQL not deployed (expected for new installations)"
    fi
}

# Validate API
validate_api() {
    print_header "Validating API"

    if kubectl get deployment benchmark-api -n benchmark-system &> /dev/null; then
        check_pass "API deployment exists"

        local api_ready=$(kubectl get deployment benchmark-api -n benchmark-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        local api_desired=$(kubectl get deployment benchmark-api -n benchmark-system -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")

        if [ "$api_ready" -eq "$api_desired" ] && [ "$api_ready" -gt 0 ]; then
            check_pass "API pods are ready ($api_ready/$api_desired)"

            # Test API health
            local api_url=$(kubectl get svc benchmark-api -n benchmark-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            if [ -n "$api_url" ]; then
                if curl -sf "http://$api_url:8000/health" > /dev/null 2>&1; then
                    check_pass "API health check passed"
                else
                    check_warn "API health check failed (may not be externally accessible yet)"
                fi
            else
                check_warn "API LoadBalancer IP not assigned yet"
            fi
        else
            check_fail "API pods not ready ($api_ready/$api_desired)"
        fi
    else
        check_warn "API not deployed (expected for new installations)"
    fi
}

# Validate monitoring
validate_monitoring() {
    print_header "Validating Monitoring"

    if kubectl get namespace monitoring &> /dev/null; then
        check_pass "monitoring namespace exists"

        # Check Prometheus
        if kubectl get statefulset -n monitoring | grep -q prometheus; then
            check_pass "Prometheus is deployed"

            local prom_ready=$(kubectl get statefulset -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].status.readyReplicas}' 2>/dev/null || echo "0")
            if [ "$prom_ready" -ge 1 ]; then
                check_pass "Prometheus is ready"
            else
                check_warn "Prometheus is not ready yet"
            fi
        else
            check_warn "Prometheus not found"
        fi

        # Check Grafana
        if kubectl get deployment -n monitoring | grep -q grafana; then
            check_pass "Grafana is deployed"

            local grafana_ready=$(kubectl get deployment -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].status.readyReplicas}' 2>/dev/null || echo "0")
            if [ "$grafana_ready" -ge 1 ]; then
                check_pass "Grafana is ready"
            else
                check_warn "Grafana is not ready yet"
            fi
        else
            check_warn "Grafana not found"
        fi
    else
        check_warn "Monitoring stack not deployed (recommended for production)"
    fi
}

# Validate service mesh
validate_service_mesh() {
    print_header "Validating Service Mesh"

    local mesh_found=false

    # Check Istio
    if kubectl get namespace istio-system &> /dev/null; then
        check_pass "Istio namespace exists"
        mesh_found=true

        if kubectl get deployment istiod -n istio-system &> /dev/null; then
            local istio_ready=$(kubectl get deployment istiod -n istio-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            if [ "$istio_ready" -ge 1 ]; then
                check_pass "Istio control plane is ready"
            else
                check_warn "Istio control plane not ready"
            fi
        fi
    fi

    # Check Cilium
    if kubectl get daemonset cilium -n kube-system &> /dev/null; then
        check_pass "Cilium is installed"
        mesh_found=true

        local cilium_desired=$(kubectl get daemonset cilium -n kube-system -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
        local cilium_ready=$(kubectl get daemonset cilium -n kube-system -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")

        if [ "$cilium_ready" -eq "$cilium_desired" ] && [ "$cilium_ready" -gt 0 ]; then
            check_pass "Cilium agents are ready ($cilium_ready/$cilium_desired)"
        else
            check_warn "Cilium agents not fully ready ($cilium_ready/$cilium_desired)"
        fi
    fi

    # Check Consul
    if kubectl get namespace consul &> /dev/null; then
        check_pass "Consul namespace exists"
        mesh_found=true

        if kubectl get statefulset consul-server -n consul &> /dev/null; then
            local consul_ready=$(kubectl get statefulset consul-server -n consul -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            if [ "$consul_ready" -ge 1 ]; then
                check_pass "Consul server is ready"
            else
                check_warn "Consul server not ready"
            fi
        fi
    fi

    # Check Linkerd
    if kubectl get namespace linkerd &> /dev/null; then
        check_pass "Linkerd namespace exists"
        mesh_found=true

        if kubectl get deployment linkerd-identity -n linkerd &> /dev/null; then
            check_pass "Linkerd control plane detected"
        fi
    fi

    if [ "$mesh_found" = false ]; then
        check_warn "No service mesh detected (optional)"
    fi
}

# Validate backups
validate_backups() {
    print_header "Validating Backup Configuration"

    if kubectl get cronjob database-backup -n benchmark-system &> /dev/null; then
        check_pass "Backup CronJob is configured"

        local last_schedule=$(kubectl get cronjob database-backup -n benchmark-system -o jsonpath='{.status.lastScheduleTime}' 2>/dev/null || echo "")
        if [ -n "$last_schedule" ]; then
            check_pass "Backup has run at least once (last: $last_schedule)"
        else
            check_warn "Backup has not run yet (scheduled for: $(kubectl get cronjob database-backup -n benchmark-system -o jsonpath='{.spec.schedule}'))"
        fi
    else
        check_warn "Backup CronJob not configured (recommended for production)"
    fi
}

# Validate secrets
validate_secrets() {
    print_header "Validating Secrets Management"

    if command_exists kubeseal; then
        check_pass "kubeseal CLI is installed"
    else
        check_warn "kubeseal not installed (needed for Sealed Secrets)"
    fi

    if kubectl get deployment sealed-secrets-controller -n kube-system &> /dev/null; then
        check_pass "Sealed Secrets controller is installed"

        local sealed_ready=$(kubectl get deployment sealed-secrets-controller -n kube-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        if [ "$sealed_ready" -ge 1 ]; then
            check_pass "Sealed Secrets controller is ready"
        else
            check_warn "Sealed Secrets controller not ready"
        fi
    else
        check_warn "Sealed Secrets not installed (recommended for production)"
    fi

    # Check for critical secrets
    if kubectl get secret postgres-secret -n benchmark-system &> /dev/null; then
        check_pass "PostgreSQL secret exists"
    else
        check_warn "PostgreSQL secret not found"
    fi
}

# Validate CI/CD
validate_cicd() {
    print_header "Validating CI/CD"

    if [ -f ".github/workflows/ci-cd.yml" ]; then
        check_pass "CI/CD workflow file exists"
    else
        check_fail "CI/CD workflow file not found"
    fi

    if [ -f ".github/workflows/security-scan.yml" ]; then
        check_pass "Security scan workflow exists"
    else
        check_warn "Security scan workflow not found"
    fi

    if [ -f ".pre-commit-config.yaml" ]; then
        check_pass "Pre-commit configuration exists"
    else
        check_warn "Pre-commit configuration not found"
    fi
}

# Validate documentation
validate_documentation() {
    print_header "Validating Documentation"

    local required_docs=(
        "README.md"
        "QUICK_START.md"
        "PRODUCTION_READY_SUMMARY.md"
        "docs/PRODUCTION_DEPLOYMENT_RUNBOOK.md"
        "docs/TESTING.md"
    )

    for doc in "${required_docs[@]}"; do
        if [ -f "$doc" ]; then
            check_pass "$doc exists"
        else
            check_fail "$doc not found"
        fi
    done
}

# Validate workloads
validate_workloads() {
    print_header "Validating Benchmark Workloads"

    local workload_files=(
        "workloads/kubernetes/workloads/baseline-http-service.yaml"
        "workloads/kubernetes/workloads/baseline-grpc-service.yaml"
        "workloads/kubernetes/workloads/http-service.yaml"
        "workloads/kubernetes/workloads/grpc-service.yaml"
        "workloads/kubernetes/workloads/websocket-service.yaml"
        "workloads/kubernetes/workloads/database-cluster.yaml"
        "workloads/kubernetes/workloads/ml-batch-job.yaml"
    )

    for workload in "${workload_files[@]}"; do
        if [ -f "$workload" ]; then
            check_pass "$(basename $workload) exists"
        else
            check_warn "$(basename $workload) not found"
        fi
    done
}

# Print summary
print_summary() {
    print_header "Validation Summary"

    local total=$((PASSED + FAILED + WARNINGS))
    echo -e "Total checks: $total"
    echo -e "${GREEN}Passed: $PASSED${NC}"
    echo -e "${RED}Failed: $FAILED${NC}"
    echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
    echo ""

    if [ $FAILED -eq 0 ]; then
        if [ $WARNINGS -eq 0 ]; then
            echo -e "${GREEN}✓ System is PRODUCTION READY!${NC}"
            exit 0
        else
            echo -e "${YELLOW}⚠ System is functional but has warnings${NC}"
            echo -e "  Review warnings above for recommended improvements"
            exit 0
        fi
    else
        echo -e "${RED}✗ System has CRITICAL ISSUES${NC}"
        echo -e "  Fix failed checks before deploying to production"
        exit 1
    fi
}

# Main execution
main() {
    echo -e "${BLUE}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════╗
║   Production Readiness Validation                     ║
║   Service Mesh Benchmark v1.0.0                       ║
╚═══════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    validate_prerequisites
    validate_kubernetes
    validate_database
    validate_api
    validate_monitoring
    validate_service_mesh
    validate_backups
    validate_secrets
    validate_cicd
    validate_documentation
    validate_workloads

    print_summary
}

# Run validation
main "$@"
