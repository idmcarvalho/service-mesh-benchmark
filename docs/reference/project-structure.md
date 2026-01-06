# Service Mesh Benchmark - Project Structure

This document describes the reorganized project structure with clear separation of responsibilities.

## Overview

The project has been reorganized into a semantic, responsibility-based structure that makes it easier to:
- Understand component purposes
- Navigate the codebase
- Add new features
- Maintain and scale the system

## Directory Structure

```
service-mesh-benchmark/
├── README.md                    # Project overview and quick start
├── Makefile                     # Master build and automation targets
├── pyproject.toml              # Python project configuration
├── generate-report.py          # Report generation script
│
├── docs/                       # All documentation (organized by topic)
│   ├── README.md              # Documentation index
│   ├── architecture/          # System design and architecture
│   ├── guides/                # Step-by-step user guides
│   ├── testing/               # Testing framework documentation
│   ├── ebpf/                  # eBPF probe documentation
│   ├── security/              # Security implementation docs
│   ├── reference/             # Reference docs and status reports
│   └── api/                   # API documentation (planned)
│
├── config/                     # Centralized configuration
│   ├── README.md
│   ├── local/                 # Local development configs
│   │   ├── docker-compose.yml
│   │   ├── .pre-commit-config.yaml
│   │   └── .yamllint.yaml
│   ├── kubernetes/            # K8s-specific configs (planned)
│   ├── monitoring/            # Observability configs
│   │   ├── prometheus.yml
│   │   └── alerts.yml
│   └── templates/             # Configuration templates
│       ├── .env.example
│       ├── backend.tf.example
│       ├── terraform.tfvars.example
│       └── ansible-inventory.ini.example
│
├── src/                        # Source code
│   ├── api/                   # FastAPI REST service
│   │   ├── main.py           # Application entry point
│   │   ├── config.py         # Configuration
│   │   ├── models.py         # Pydantic models
│   │   ├── database.py       # Database layer
│   │   ├── state.py          # Application state
│   │   └── endpoints/        # API route handlers
│   │       ├── health.py
│   │       ├── benchmarks.py
│   │       ├── metrics.py
│   │       ├── reports.py
│   │       ├── kubernetes.py
│   │       └── ebpf.py
│   │
│   ├── tests/                 # Test suite (organized by phase)
│   │   ├── conftest.py       # pytest fixtures
│   │   ├── models.py         # Test models
│   │   ├── run_tests.py      # Test orchestrator
│   │   ├── phase1_predeployment/
│   │   │   └── test_validation.py
│   │   ├── phase2_infrastructure/
│   │   │   └── test_readiness.py
│   │   ├── phase3_baseline/
│   │   │   └── test_performance.py
│   │   ├── phase4_servicemesh/
│   │   │   └── test_mesh.py
│   │   ├── phase6_comparative/
│   │   │   └── test_analysis.py
│   │   └── phase7_stress/
│   │       └── test_stress.py
│   │
│   └── probes/                # eBPF kernel probes
│       ├── Cargo.toml        # Rust workspace config
│       ├── README.md
│       ├── common/           # Shared types and constants
│       │   └── src/
│       └── latency/          # Latency measurement probe
│           ├── kernel/       # Kernel-space eBPF program
│           │   └── src/
│           └── daemon/       # User-space daemon
│               └── src/
│
├── workloads/                 # Benchmark workloads
│   ├── README.md
│   ├── kubernetes/           # K8s manifests
│   │   ├── workloads/       # Deployment manifests
│   │   ├── rbac/            # RBAC configurations
│   │   ├── network-policies/ # Network policies
│   │   ├── database/        # Stateful workloads
│   │   └── backup/          # Backup automation
│   │
│   ├── scripts/             # Benchmark execution scripts
│   │   ├── runners/         # Test execution
│   │   │   ├── http-load-test.sh
│   │   │   ├── grpc-test.sh
│   │   │   ├── websocket-test.sh
│   │   │   └── ml-workload.sh
│   │   ├── metrics/         # Metrics collection
│   │   │   ├── collect-metrics.sh
│   │   │   ├── collect-ebpf-metrics.sh
│   │   │   └── compare-overhead.sh
│   │   ├── validation/      # Validation scripts
│   │   │   ├── test-network-policies.sh
│   │   │   └── test-l7-policies.sh
│   │   └── results/         # Output directory
│   │
│   └── docker/              # Container images
│       ├── api/
│       ├── health-check/
│       └── ml-workload/
│
├── infrastructure/            # Infrastructure as Code
│   ├── README.md
│   ├── terraform/           # Infrastructure provisioning
│   │   └── oracle-cloud/   # OCI provider config
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       ├── outputs.tf
│   │       └── scripts/
│   │
│   └── ansible/             # Configuration management
│       ├── inventory/
│       └── playbooks/
│           ├── setup-istio.yml
│           ├── setup-cilium.yml
│           ├── setup-consul.yml
│           └── deploy-workloads.yml
│
├── tools/                     # Utilities and CI/CD
│   ├── README.md
│   ├── scripts/
│   │   ├── security/        # Security utilities
│   │   │   ├── apply-security-contexts.sh
│   │   │   └── validate-production.sh
│   │   ├── maintenance/     # Operational scripts
│   │   │   ├── backup-to-oci.sh
│   │   │   └── init-db.sql
│   │   └── development/     # Dev utilities
│   │       ├── fix-shell-security.sh
│   │       └── auto-fix-shell-quotes.py
│   │
│   └── ci/                  # CI/CD pipelines
│       └── .github/
│           └── workflows/
│               ├── test.yml
│               ├── ci-cd.yml
│               ├── benchmark.yml
│               └── security-scan.yml
│
├── develop/                   # Development environment
│   ├── README.md
│   ├── .devcontainer/       # VS Code Dev Container
│   │   ├── Dockerfile
│   │   ├── devcontainer.json
│   │   └── scripts/
│   ├── Makefile             # Build targets (copy)
│   └── pyproject.toml       # Python config (copy)
│
└── monitoring/                # Observability (to be refactored)
    ├── prometheus/
    └── grafana/
```

## Component Responsibilities

### `/docs` - Documentation
**Purpose**: All project documentation organized by topic

**Contents**:
- Architecture diagrams and design docs
- User guides and tutorials
- Testing methodology
- Security implementation
- Reference materials

**Target Audience**: Developers, operators, users

### `/config` - Configuration
**Purpose**: Centralized configuration management

**Contents**:
- Local development configs (docker-compose, linting)
- Infrastructure config templates
- Monitoring configurations
- Environment variable templates

**Key Feature**: All sensitive configs use `.example` suffix

### `/src` - Source Code
**Purpose**: All application source code

**Components**:
- **api/** - FastAPI REST service for orchestration
- **tests/** - Phase-organized test suite
- **probes/** - Rust/eBPF kernel probes with kernel/daemon split

**Language Stack**: Python (API, tests), Rust (eBPF)

### `/workloads` - Benchmark Workloads
**Purpose**: Workload definitions and execution

**Components**:
- **kubernetes/** - Deployment manifests, RBAC, policies
- **scripts/** - Benchmark runners and metrics collection
- **docker/** - Container image definitions

**Workload Types**: HTTP, gRPC, WebSocket, Database, ML

### `/infrastructure` - Infrastructure as Code
**Purpose**: Cluster provisioning and configuration

**Components**:
- **terraform/** - OCI infrastructure provisioning
- **ansible/** - Service mesh installation and configuration

**Workflow**: Terraform → Ansible → Kubernetes

### `/tools` - Utilities and Automation
**Purpose**: Development tools and CI/CD

**Components**:
- **scripts/** - Organized by purpose (security, maintenance, dev)
- **ci/** - GitHub Actions workflows

**Functions**: Security, backup, linting, testing, deployment

### `/develop` - Development Environment
**Purpose**: Developer onboarding and local setup

**Components**:
- Dev container configuration
- Build tools (Makefile)
- Development workflows

**Benefits**: Consistent dev environment across team

## Key Improvements

### Before vs After

| Aspect | Before | After |
|--------|--------|-------|
| **Documentation** | Scattered in root + docs/ | Organized in /docs with hierarchy |
| **Configuration** | Multiple locations | Centralized in /config |
| **Tests** | Flat structure | Phase-based organization |
| **eBPF Code** | Mixed kernel/userspace | Clear kernel/daemon split |
| **Infrastructure** | Separate terraform/ansible | Unified in /infrastructure |
| **Utilities** | Generic /scripts | Purpose-organized in /tools |
| **Dev Setup** | Root-level files | Dedicated /develop directory |

### Benefits

1. **Clearer Navigation**
   - Obvious where to find components
   - Logical grouping by responsibility
   - Easier onboarding

2. **Better Scalability**
   - Easy to add new workloads
   - Test phases can grow independently
   - Multiple probe types supported

3. **Improved Maintenance**
   - Related files grouped together
   - Configuration centralized
   - Documentation co-located with code

4. **Enhanced CI/CD**
   - Clear build artifacts locations
   - Organized pipeline definitions
   - Explicit dependencies

## Migration Path

For existing code that references old paths:

| Old Path | New Path | Notes |
|----------|----------|-------|
| `api/` | `src/api/` | Update imports in Python |
| `tests/` | `src/tests/` | Update pytest paths |
| `ebpf-probes/` | `src/probes/` | Update Cargo.toml |
| `kubernetes/` | `workloads/kubernetes/` | Update kubectl paths |
| `benchmarks/scripts/` | `workloads/scripts/` | Update script paths |
| `terraform/` | `infrastructure/terraform/` | Update CI/CD |
| `ansible/` | `infrastructure/ansible/` | Update playbooks |
| `.github/` | `tools/ci/.github/` | Update workflow paths |
| `scripts/` | `tools/scripts/` | Update script calls |
| `.devcontainer/` | `develop/.devcontainer/` | Update VS Code |
| `docker-compose.yml` | `config/local/docker-compose.yml` | Update commands |

## Quick Reference

### Common Tasks

```bash
# View documentation
cd docs/
cat README.md

# Configure environment
cp config/templates/.env.example .env
# Edit .env

# Run tests
cd src/tests
pytest

# Build eBPF probes
cd src/probes
cargo build --release

# Deploy workloads
kubectl apply -f workloads/kubernetes/

# Run benchmarks
./workloads/scripts/runners/http-load-test.sh

# Provision infrastructure
cd infrastructure/terraform/oracle-cloud
terraform apply

# Use development environment
code .  # Opens in dev container
```

## Next Steps

1. **Update Path References**: Update Makefile, scripts, and configs with new paths
2. **Update CI/CD**: Modify GitHub Actions workflows for new structure
3. **Update Documentation**: Ensure all docs reference correct paths
4. **Test Migration**: Run full test suite to verify paths
5. **Clean Up**: Remove old empty directories

## Contributing

When adding new components:
- Place in the appropriate top-level directory
- Update the README in that directory
- Add to this PROJECT_STRUCTURE.md
- Update relevant documentation
- Follow the established naming conventions

## Questions?

- Architecture: See [docs/architecture/](docs/architecture/)
- Development: See [develop/README.md](develop/README.md)
- Deployment: See [infrastructure/README.md](infrastructure/README.md)
- Testing: See [docs/testing/](docs/testing/)
