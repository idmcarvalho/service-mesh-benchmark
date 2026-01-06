# Migration Guide - Project Reorganization

This guide helps you update references to the new project structure.

## Overview of Changes

The project has been reorganized from a component-type structure to a responsibility-based structure. This document outlines what changed and how to update your code.

## Directory Moves Summary

| Old Location | New Location | Status |
|-------------|--------------|--------|
| `api/` | `src/api/` | ✅ Moved |
| `tests/` | `src/tests/` | ✅ Moved + Reorganized |
| `ebpf-probes/` | `src/probes/` | ✅ Moved + Restructured |
| `kubernetes/` | `workloads/kubernetes/` | ✅ Moved |
| `benchmarks/scripts/` | `workloads/scripts/` | ✅ Moved |
| `docker/` | `workloads/docker/` | ✅ Moved |
| `terraform/` | `infrastructure/terraform/` | ✅ Moved |
| `ansible/` | `infrastructure/ansible/` | ✅ Moved |
| `.github/` | `tools/ci/.github/` | ✅ Moved |
| `scripts/` | `tools/scripts/` | ✅ Moved + Organized |
| `.devcontainer/` | `develop/.devcontainer/` | ✅ Moved |
| `docker-compose.yml` | `config/local/docker-compose.yml` | ✅ Moved |
| `.pre-commit-config.yaml` | `config/local/.pre-commit-config.yaml` | ✅ Moved |
| Root `*.md` files | `docs/*/` | ✅ Organized by topic |

## Step-by-Step Migration

### 1. Update Python Imports (API)

**Before**:
```python
from api.config import settings
from api.models import BenchmarkRequest
from api.endpoints.health import router
```

**After**:
```python
from src.api.config import settings
from src.api.models import BenchmarkRequest
from src.api.endpoints.health import router
```

**Fix Command**:
```bash
# Update all Python imports
find . -name "*.py" -type f -exec sed -i 's/from api\./from src.api./g' {} +
find . -name "*.py" -type f -exec sed -i 's/import api\./import src.api./g' {} +
```

### 2. Update Test Paths

**Before**:
```python
# tests/test_phase1_predeployment.py
from tests.conftest import client
import tests.models as test_models
```

**After**:
```python
# src/tests/phase1_predeployment/test_validation.py
from src.tests.conftest import client
import src.tests.models as test_models
```

**Test Structure Changes**:
- `tests/test_phase1_*.py` → `src/tests/phase1_predeployment/test_validation.py`
- `tests/test_phase2_*.py` → `src/tests/phase2_infrastructure/test_readiness.py`
- `tests/test_phase3_*.py` → `src/tests/phase3_baseline/test_performance.py`
- `tests/test_phase4_*.py` → `src/tests/phase4_servicemesh/test_mesh.py`
- `tests/test_phase6_*.py` → `src/tests/phase6_comparative/test_analysis.py`
- `tests/test_phase7_*.py` → `src/tests/phase7_stress/test_stress.py`

**Fix Command**:
```bash
# Update pytest paths in pyproject.toml
sed -i 's/testpaths = \["tests"\]/testpaths = ["src\/tests"]/' pyproject.toml
```

### 3. Update eBPF Workspace

**Before** (`ebpf-probes/Cargo.toml`):
```toml
[workspace]
members = [
    "common",
    "latency-probe/latency-probe-ebpf",
    "latency-probe/latency-probe-userspace",
]
```

**After** (`src/probes/Cargo.toml`):
```toml
[workspace]
members = [
    "common",
    "latency/kernel",
    "latency/daemon",
]
```

**Already Updated**: ✅ Cargo.toml has been updated

### 4. Update Kubernetes Manifests

**Before**:
```bash
kubectl apply -f kubernetes/workloads/
kubectl apply -f kubernetes/rbac/
```

**After**:
```bash
kubectl apply -f workloads/kubernetes/workloads/
kubectl apply -f workloads/kubernetes/rbac/
```

**Fix Command**:
```bash
# Update all kubectl commands in scripts
find . -name "*.sh" -type f -exec sed -i 's|kubectl apply -f kubernetes/|kubectl apply -f workloads/kubernetes/|g' {} +
```

### 5. Update Benchmark Scripts

**Before**:
```bash
./benchmarks/scripts/http-load-test.sh
./benchmarks/scripts/collect-metrics.sh
```

**After**:
```bash
./workloads/scripts/runners/http-load-test.sh
./workloads/scripts/metrics/collect-metrics.sh
```

**Script Organization**:
- `benchmarks/scripts/http-load-test.sh` → `workloads/scripts/runners/http-load-test.sh`
- `benchmarks/scripts/grpc-test.sh` → `workloads/scripts/runners/grpc-test.sh`
- `benchmarks/scripts/collect-metrics.sh` → `workloads/scripts/metrics/collect-metrics.sh`
- `benchmarks/scripts/collect-ebpf-metrics.sh` → `workloads/scripts/metrics/collect-ebpf-metrics.sh`

### 6. Update Docker Compose

**Before**:
```bash
docker-compose up
```

**After**:
```bash
docker-compose -f config/local/docker-compose.yml up
```

**Create Symlink** (Optional):
```bash
ln -s config/local/docker-compose.yml docker-compose.yml
```

### 7. Update Terraform Paths

**Before**:
```bash
cd terraform/oracle-cloud
terraform init
```

**After**:
```bash
cd infrastructure/terraform/oracle-cloud
terraform init
```

**Fix CI/CD**:
```yaml
# .github/workflows/ci-cd.yml
# Before
working-directory: terraform/oracle-cloud

# After
working-directory: infrastructure/terraform/oracle-cloud
```

### 8. Update Ansible Playbooks

**Before**:
```bash
cd ansible
ansible-playbook playbooks/setup-istio.yml
```

**After**:
```bash
cd infrastructure/ansible
ansible-playbook playbooks/setup-istio.yml
```

### 9. Update CI/CD Workflows

**GitHub Actions Path**:
- Workflows moved: `.github/workflows/` → `tools/ci/.github/workflows/`

**Create Symlink**:
```bash
ln -s tools/ci/.github .github
```

### 10. Update Utility Scripts

**Before**:
```bash
./scripts/apply-security-contexts.sh
./scripts/backup-to-oci.sh
```

**After**:
```bash
./tools/scripts/security/apply-security-contexts.sh
./tools/scripts/maintenance/backup-to-oci.sh
```

**Script Organization**:
- Security scripts → `tools/scripts/security/`
- Maintenance scripts → `tools/scripts/maintenance/`
- Development scripts → `tools/scripts/development/`

### 11. Update Documentation References

**Before**:
```markdown
See [TESTING.md](TESTING.md) for details
See [architecture.md](docs/architecture.md)
```

**After**:
```markdown
See [Testing Documentation](docs/testing/TESTING.md) for details
See [Architecture](docs/architecture/architecture.md)
```

### 12. Update Dev Container

**VS Code Settings**:
The devcontainer is now at `develop/.devcontainer/devcontainer.json`

**Update workspace file**:
```json
{
  "folders": [
    {
      "path": "."
    }
  ],
  "settings": {
    "python.defaultInterpreterPath": "/usr/local/bin/python",
    "python.testing.pytestPath": "pytest",
    "python.testing.pytestArgs": ["src/tests"]
  }
}
```

## Automated Migration Script

Run this script to update common path references:

```bash
#!/bin/bash
# update-paths.sh

set -euo pipefail

echo "Updating Python imports..."
find . -name "*.py" -type f -not -path "*/.*" \
  -exec sed -i 's/from api\./from src.api./g' {} +

find . -name "*.py" -type f -not -path "*/.*" \
  -exec sed -i 's/import api\./import src.api./g' {} +

find . -name "*.py" -type f -not -path "*/.*" \
  -exec sed -i 's/from tests\./from src.tests./g' {} +

echo "Updating kubectl commands..."
find . -name "*.sh" -type f -not -path "*/.*" \
  -exec sed -i 's|kubernetes/|workloads/kubernetes/|g' {} +

echo "Updating benchmark script paths..."
find . -name "*.sh" -type f -not -path "*/.*" \
  -exec sed -i 's|benchmarks/scripts/|workloads/scripts/|g' {} +

echo "Updating terraform paths..."
find . -name "*.yml" -o -name "*.yaml" -type f -not -path "*/.*" \
  -exec sed -i 's|terraform/oracle-cloud|infrastructure/terraform/oracle-cloud|g' {} +

echo "Updating ansible paths..."
find . -name "*.yml" -o -name "*.yaml" -type f -not -path "*/.*" \
  -exec sed -i 's|ansible/playbooks|infrastructure/ansible/playbooks|g' {} +

echo "Creating symlinks..."
ln -sf config/local/docker-compose.yml docker-compose.yml 2>/dev/null || true
ln -sf tools/ci/.github .github 2>/dev/null || true

echo "Migration complete! Please review changes with 'git diff'"
```

## Makefile Updates Required

The root `Makefile` needs updates for new paths. Key sections to update:

### Test Targets
```makefile
# Before
test:
	pytest tests/

# After
test:
	pytest src/tests/
```

### Build Targets
```makefile
# Before
build-ebpf:
	cd ebpf-probes && cargo build --release

# After
build-ebpf:
	cd src/probes && cargo build --release
```

### Deploy Targets
```makefile
# Before
deploy-workloads:
	kubectl apply -f kubernetes/workloads/

# After
deploy-workloads:
	kubectl apply -f workloads/kubernetes/workloads/
```

### Docker Targets
```makefile
# Before
docker-up:
	docker-compose up -d

# After
docker-up:
	docker-compose -f config/local/docker-compose.yml up -d
```

## Verification Checklist

After migration, verify:

- [ ] Python imports work: `python -c "from src.api.main import app"`
- [ ] Tests run: `pytest src/tests/`
- [ ] eBPF builds: `cd src/probes && cargo build`
- [ ] Kubernetes manifests valid: `kubectl apply --dry-run=client -f workloads/kubernetes/`
- [ ] Docker Compose works: `docker-compose -f config/local/docker-compose.yml config`
- [ ] Scripts execute: `./workloads/scripts/runners/http-load-test.sh --help`
- [ ] CI/CD workflows valid: Check `.github/workflows/` (or symlink)
- [ ] Documentation links work: Check all markdown files
- [ ] Terraform plans: `cd infrastructure/terraform/oracle-cloud && terraform plan`
- [ ] Ansible syntax: `ansible-playbook --syntax-check infrastructure/ansible/playbooks/*.yml`

## Rollback Procedure

If you need to rollback:

```bash
# Undo git moves (if not committed)
git reset --hard HEAD

# If committed, revert the commit
git revert <commit-hash>

# Manual rollback
mv src/api api
mv src/tests tests
mv src/probes ebpf-probes
mv workloads/kubernetes kubernetes
mv workloads/scripts benchmarks/scripts
# etc...
```

## Common Issues

### Issue: Import errors in Python
**Solution**: Update PYTHONPATH or install in editable mode
```bash
pip install -e .
```

### Issue: Pytest can't find tests
**Solution**: Update `pyproject.toml`:
```toml
[tool.pytest.ini_options]
testpaths = ["src/tests"]
```

### Issue: Docker Compose fails
**Solution**: Use full path:
```bash
docker-compose -f config/local/docker-compose.yml up
```

### Issue: eBPF build fails
**Solution**: Update workspace members in `src/probes/Cargo.toml`

### Issue: CI/CD workflows not found
**Solution**: Create symlink:
```bash
ln -s tools/ci/.github .github
```

## Getting Help

- Check [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) for new layout
- See component-specific READMEs in each directory
- Review [docs/guides/](docs/guides/) for updated guides
- Open an issue if you find broken references

## Timeline

- **Phase 1**: Directory reorganization ✅ Complete
- **Phase 2**: Path reference updates (This guide) 🔄 In Progress
- **Phase 3**: Documentation updates 📝 Next
- **Phase 4**: CI/CD validation ✓ To Do
- **Phase 5**: Final cleanup 🧹 To Do

## Contributing

When contributing after this reorganization:
1. Use new paths in your code
2. Update documentation with correct paths
3. Test your changes with new structure
4. Update this guide if you find missing migration steps
