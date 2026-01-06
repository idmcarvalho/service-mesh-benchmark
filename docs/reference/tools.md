# Tools Directory

This directory contains utility scripts and CI/CD configurations organized by purpose.

## Directory Structure

### [scripts/](scripts/)
Utility scripts organized by function:

#### [security/](scripts/security/)
Security-related scripts:
- `apply-security-contexts.sh` - Apply Kubernetes security contexts to workloads
- `validate-production.sh` - Pre-deployment security validation

#### [maintenance/](scripts/maintenance/)
Maintenance and operational scripts:
- `backup-to-oci.sh` - Backup benchmark results to Oracle Cloud Object Storage
- `init-db.sql` - Database initialization script

#### [development/](scripts/development/)
Development and code quality scripts:
- `fix-shell-security.sh` - Bash script linting and security fixes
- `auto-fix-shell-quotes.py` - Automated shell quoting corrections

### [ci/](ci/)
CI/CD pipeline configurations:
- `.github/workflows/` - GitHub Actions workflows
  - `test.yml` - Python test execution
  - `ci-cd.yml` - Build, push, deployment pipeline
  - `benchmark.yml` - Scheduled benchmark runs
  - `security-scan.yml` - Code security scanning

## Usage

### Security Scripts
```bash
# Apply security contexts to Kubernetes workloads
./tools/scripts/security/apply-security-contexts.sh

# Validate production readiness
./tools/scripts/security/validate-production.sh
```

### Maintenance Scripts
```bash
# Backup results to OCI Object Storage
./tools/scripts/maintenance/backup-to-oci.sh

# Initialize database
psql -f tools/scripts/maintenance/init-db.sql
```

### Development Scripts
```bash
# Fix shell script security issues
./tools/scripts/development/fix-shell-security.sh

# Auto-fix shell quoting
python3 tools/scripts/development/auto-fix-shell-quotes.py
```

## CI/CD Pipelines

### Test Pipeline (`test.yml`)
Runs on every push and pull request:
1. Lint Python code (ruff, mypy)
2. Run pytest test suite
3. Generate coverage reports
4. Upload artifacts

### CI/CD Pipeline (`ci-cd.yml`)
Runs on push to main:
1. Build Docker images
2. Push to container registry
3. Deploy to staging environment
4. Run integration tests
5. Deploy to production (manual approval)

### Benchmark Pipeline (`benchmark.yml`)
Scheduled daily runs:
1. Deploy benchmark workloads
2. Execute all benchmark scripts
3. Collect metrics
4. Generate comparison reports
5. Archive results

### Security Scan Pipeline (`security-scan.yml`)
Runs on every push:
1. Scan Python code with bandit
2. Scan Docker images with trivy
3. Check dependencies for vulnerabilities
4. Generate security reports

## Adding New Tools

When adding new utility scripts:
1. Place in appropriate subdirectory by purpose
2. Make scripts executable: `chmod +x script.sh`
3. Add shebang line: `#!/usr/bin/env bash` or `#!/usr/bin/env python3`
4. Document usage in this README
5. Add to appropriate Makefile target if needed

## Best Practices

- **Idempotent scripts** - Scripts should be safe to run multiple times
- **Error handling** - Use `set -euo pipefail` in bash scripts
- **Logging** - Include informative output and error messages
- **Configuration** - Use environment variables or config files, not hardcoded values
- **Testing** - Test scripts in dev environment before production use
