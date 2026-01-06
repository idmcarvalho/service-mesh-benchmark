# Service Mesh Benchmark - Documentation

This directory contains all documentation for the Service Mesh Benchmark project.

## Directory Structure

### [Architecture](architecture/)
System design and architecture documentation:
- [architecture.md](architecture/architecture.md) - Complete system architecture overview

### [Guides](guides/)
Step-by-step guides for users and developers:
- [quick-start.md](guides/quick-start.md) - Quick start guide for getting started
- [quickstart.md](guides/quickstart.md) - Quick start guide
- [deployment.md](guides/deployment.md) - Deployment guide
- [migration-guide.md](guides/migration-guide.md) - Migration guide for upgrading
- [production-deployment.md](guides/production-deployment.md) - Production deployment runbook
- [oracle-cloud-deployment.md](guides/oracle-cloud-deployment.md) - Oracle Cloud deployment guide
- [terraform-ansible-deployment.md](guides/terraform-ansible-deployment.md) - Terraform and Ansible deployment
- [ansible.md](guides/ansible.md) - Ansible configuration and usage
- [terraform.md](guides/terraform.md) - Terraform infrastructure as code
- [infrastructure.md](guides/infrastructure.md) - Infrastructure setup and management

### [Testing](testing/)
Testing framework and methodology documentation:
- [tests.md](testing/tests.md) - Test suite overview
- [TESTING.md](testing/TESTING.md) - Testing framework overview
- [TESTING_DIAGRAM.md](testing/TESTING_DIAGRAM.md) - Testing workflow diagrams
- [TESTING_IMPLEMENTATION_SUMMARY.md](testing/TESTING_IMPLEMENTATION_SUMMARY.md) - Implementation details
- [TESTING_QUICK_REFERENCE.md](testing/TESTING_QUICK_REFERENCE.md) - Quick reference guide
- [COVERAGE.md](testing/COVERAGE.md) - Coverage analysis
- [COVERAGE_QUICK_REFERENCE.md](testing/COVERAGE_QUICK_REFERENCE.md) - Coverage quick reference

### [eBPF](ebpf/)
eBPF probe documentation and implementation details:
- [probes.md](ebpf/probes.md) - eBPF probes overview
- [probes-implementation-status.md](ebpf/probes-implementation-status.md) - Probe implementation status
- [IMPLEMENTATION_SUMMARY.md](ebpf/IMPLEMENTATION_SUMMARY.md) - eBPF implementation summary
- [ebpf-features.md](ebpf/ebpf-features.md) - Feature documentation
- [EBPF_FEATURES_SUMMARY.md](ebpf/EBPF_FEATURES_SUMMARY.md) - Features summary
- [JIT_OPTIMIZATION.md](ebpf/JIT_OPTIMIZATION.md) - JIT compilation optimization

### [Security](security/)
Security hardening, audit findings, and implementation:
- [SECURITY_IMPLEMENTATION.md](security/SECURITY_IMPLEMENTATION.md) - Security implementation details
- [SECURITY_AUDIT_FINDINGS.md](security/SECURITY_AUDIT_FINDINGS.md) - Audit findings and remediation
- [SECURITY_HARDENING.md](security/SECURITY_HARDENING.md) - Hardening guidelines
- [SECURITY_QUICKSTART.md](security/SECURITY_QUICKSTART.md) - Security quick start guide

### [Reference](reference/)
Reference documentation, status reports, and historical records:
- [project-structure.md](reference/project-structure.md) - Project structure and organization
- [production-ready-changes.md](reference/production-ready-changes.md) - Production readiness changes
- [reorganization-complete.md](reference/reorganization-complete.md) - Project reorganization completion
- [reorganization-summary.md](reference/reorganization-summary.md) - Project reorganization summary
- [config.md](reference/config.md) - Configuration reference
- [workloads.md](reference/workloads.md) - Workloads reference
- [tools.md](reference/tools.md) - Tools reference
- [develop.md](reference/develop.md) - Development reference
- [frontend.md](reference/frontend.md) - Frontend reference
- [CRITICAL_FIXES_APPLIED.md](reference/CRITICAL_FIXES_APPLIED.md) - Critical fixes applied
- [SECURITY_FIXES_COMPLETE_SUMMARY.md](reference/SECURITY_FIXES_COMPLETE_SUMMARY.md) - Security fixes summary
- [PROJECT_ANALYSIS_REPORT.md](reference/PROJECT_ANALYSIS_REPORT.md) - Project analysis report
- [HIGH_PRIORITY_FIXES_STATUS.md](reference/HIGH_PRIORITY_FIXES_STATUS.md) - High priority fixes status
- [PYTHON_QUALITY_IMPROVEMENTS.md](reference/PYTHON_QUALITY_IMPROVEMENTS.md) - Python quality improvements
- [PRODUCTION_READY_SUMMARY.md](reference/PRODUCTION_READY_SUMMARY.md) - Production ready summary
- [IMPLEMENTATION_COMPLETE.md](reference/IMPLEMENTATION_COMPLETE.md) - Implementation completion
- [FRONTEND_DESIGN.md](reference/FRONTEND_DESIGN.md) - Frontend design

### [API](api/)
API documentation and endpoint references:
- [api.md](api/api.md) - API overview and reference

## Contributing

When adding new documentation:
1. Place it in the appropriate subdirectory based on its purpose
2. Update this README.md with a link to the new document
3. Use clear, descriptive filenames (lowercase with hyphens preferred)
4. Include a table of contents for documents longer than 100 lines
