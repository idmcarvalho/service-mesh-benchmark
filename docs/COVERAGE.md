# Code Coverage Guide

This document explains how to use code coverage tracking for the Service Mesh Benchmark testing suite.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Coverage Commands](#coverage-commands)
- [Understanding Reports](#understanding-reports)
- [CI/CD Integration](#cicd-integration)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

## Overview

Code coverage measures which parts of your test code are executed during test runs. This helps identify:

- **Untested code paths** - Areas that need more tests
- **Test effectiveness** - How well your tests exercise the codebase
- **Quality metrics** - Quantifiable measure of test completeness

### Coverage Configuration

Coverage is configured in:
- [tests/.coveragerc](../tests/.coveragerc) - Coverage.py configuration
- [tests/pytest.ini](../tests/pytest.ini) - Pytest coverage settings

### Coverage Threshold

The project has a **70% minimum coverage threshold** configured. Tests will report a warning if coverage falls below this level.

## Quick Start

### 1. Install Dependencies

```bash
# Install coverage tools
make test-deps
```

This installs:
- `pytest-cov==4.1.0` - Pytest coverage plugin
- `coverage[toml]==7.4.0` - Coverage.py with TOML support

### 2. Run Tests with Coverage

```bash
# Run all tests with coverage
make coverage

# Or run specific phase with coverage
make coverage-phase1
```

### 3. View Coverage Report

```bash
# Open HTML report in browser
make coverage-open

# Or view in terminal
make coverage-report
```

## Configuration

### Coverage Configuration File

The [tests/.coveragerc](../tests/.coveragerc) file controls coverage behavior:

```ini
[run]
source = .              # Code to measure
branch = True           # Measure branch coverage
parallel = True         # Support parallel execution

[report]
precision = 2           # Decimal places for percentages
show_missing = True     # Show missing line numbers
fail_under = 70.0       # Minimum coverage threshold
sort = Cover            # Sort by coverage percentage

[html]
directory = htmlcov     # HTML report directory
```

### Excluded Lines

The following patterns are excluded from coverage:

```python
# Pragmas
pragma: no cover

# Debugging
def __repr__
def __str__

# Defensive code
raise AssertionError
raise NotImplementedError

# Script entry points
if __name__ == .__main__.:

# Type checking
if TYPE_CHECKING:

# Abstract methods
@abstractmethod

# Placeholders
pass
...
```

## Coverage Commands

### Basic Commands

```bash
# Run all tests with coverage (all formats)
make coverage

# Generate HTML report only
make coverage-html

# Show terminal report with missing lines
make coverage-report

# Generate XML report (for CI/CD)
make coverage-xml

# Generate JSON report
make coverage-json
```

### Phase-Specific Coverage

```bash
# Phase 1: Pre-deployment validation
make coverage-phase1

# Phase 2: Infrastructure validation
make coverage-phase2

# Phase 3: Baseline performance
make coverage-phase3

# Phase 4: Service mesh (specify MESH_TYPE)
make coverage-phase4 MESH_TYPE=istio

# Phase 6: Comparative analysis
make coverage-phase6

# Phase 7: Stress and edge cases
make coverage-phase7
```

### Mesh-Specific Coverage

```bash
# Baseline tests
make coverage-baseline

# Istio tests
make coverage-istio

# Cilium tests
make coverage-cilium
```

### Utility Commands

```bash
# Open HTML report in browser
make coverage-open

# Clean all coverage artifacts
make coverage-clean

# Combine coverage from parallel runs
make coverage-combine

# Generate coverage badge (requires coverage-badge package)
make coverage-badge
```

## Understanding Reports

### HTML Report

The HTML report provides the most detailed view:

```bash
make coverage-html
make coverage-open
```

The report includes:
- **Overview** - Overall coverage percentage
- **File List** - Coverage per file with color coding
- **Source View** - Line-by-line coverage highlighting
- **Branch Coverage** - If/else branch execution tracking

**Color Coding:**
- 🟢 **Green** - Lines executed during tests
- 🔴 **Red** - Lines not executed
- 🟡 **Yellow** - Partially covered (branches)

### Terminal Report

Quick coverage summary in your terminal:

```bash
make coverage-report
```

Example output:
```
Name                               Stmts   Miss Branch BrPart  Cover   Missing
------------------------------------------------------------------------------
conftest.py                          150     10     40      2    92.5%   45-48, 203
test_phase1_predeployment.py         320     25     60      5    90.2%   156-162, 301-305
test_phase2_infrastructure.py        280     30     55      8    87.3%   89-95, 234-240
test_phase3_baseline.py              250     20     50      3    91.5%   45-52, 189
------------------------------------------------------------------------------
TOTAL                               1000     85    205     18    89.8%
```

**Columns:**
- **Stmts** - Total statements
- **Miss** - Statements not executed
- **Branch** - Total branches (if/else)
- **BrPart** - Partially covered branches
- **Cover** - Coverage percentage
- **Missing** - Line numbers not covered

### XML Report (CI/CD)

Machine-readable format for CI/CD tools:

```bash
make coverage-xml
```

Output: `tests/coverage.xml` (Cobertura format)

### JSON Report

Structured data format:

```bash
make coverage-json
```

Output: `tests/coverage.json`

Example structure:
```json
{
  "meta": {
    "version": "7.4.0",
    "timestamp": "2025-01-15T10:30:00",
    "branch_coverage": true
  },
  "files": {
    "test_phase1_predeployment.py": {
      "summary": {
        "covered_lines": 295,
        "num_statements": 320,
        "percent_covered": 92.19,
        "missing_lines": 25,
        "excluded_lines": 0
      }
    }
  },
  "totals": {
    "covered_lines": 915,
    "num_statements": 1000,
    "percent_covered": 91.5
  }
}
```

## CI/CD Integration

### GitHub Actions

Coverage is automatically collected in CI/CD:

#### Pre-deployment Tests (Phase 1)

```yaml
- name: Run Phase 1 Tests
  run: |
    cd tests
    pytest -v -m phase1 \
      --cov=. \
      --cov-report=html \
      --cov-report=xml \
      --cov-report=term-missing

- name: Upload Coverage to Codecov
  uses: codecov/codecov-action@v3
  with:
    file: tests/coverage.xml
    flags: phase1
```

#### Integration Tests

```yaml
- name: Generate Coverage Report
  run: |
    cd tests
    coverage combine
    coverage report
    coverage html
    coverage xml

- name: Upload Coverage to Codecov
  uses: codecov/codecov-action@v3
  with:
    file: tests/coverage.xml
    flags: integration

- name: Comment Coverage on PR
  uses: py-cov-action/python-coverage-comment-action@v3
  with:
    GITHUB_TOKEN: ${{ github.token }}
    MINIMUM_GREEN: 70
    MINIMUM_ORANGE: 50
```

### Codecov Integration

Coverage reports are uploaded to [Codecov](https://codecov.io):

1. **Automatic on PRs** - Coverage reports commented on pull requests
2. **Trend Tracking** - Historical coverage over time
3. **Diff Coverage** - Shows coverage changes in PRs
4. **Badge** - Coverage badge for README

To set up:
1. Sign up at [codecov.io](https://codecov.io)
2. Add repository
3. Add `CODECOV_TOKEN` to GitHub secrets (if private repo)

### Coverage Badge

Add to your README.md:

```markdown
[![codecov](https://codecov.io/gh/YOUR_USERNAME/service-mesh-benchmark/branch/main/graph/badge.svg)](https://codecov.io/gh/YOUR_USERNAME/service-mesh-benchmark)
```

Or generate locally:

```bash
# Install coverage-badge
pip install coverage-badge

# Generate badge
make coverage-badge
```

## Best Practices

### 1. Run Coverage Regularly

```bash
# Before committing
make coverage-report

# Full check before PR
make coverage
make coverage-open
```

### 2. Focus on Critical Code

Not all code needs 100% coverage. Prioritize:
- ✅ Core test logic
- ✅ Fixtures and utilities
- ✅ Critical validation functions
- ⚠️ Error handling paths
- ❌ Simple getters/setters (use `# pragma: no cover`)

### 3. Use Coverage to Find Gaps

```bash
# Find files with low coverage
make coverage-report | grep -E "^.*\s+[0-6][0-9]\.[0-9]%"

# View specific file
make coverage-html
make coverage-open
# Navigate to low-coverage files
```

### 4. Parallel Test Coverage

When running tests in parallel:

```bash
# Run tests
cd tests
pytest -v -n auto --cov=. --cov-append

# Combine coverage data
make coverage-combine
```

### 5. Coverage in Development

```bash
# Quick check during development
cd tests
pytest test_phase1_predeployment.py::test_specific_function -v --cov=. --cov-report=term-missing

# Watch mode (with pytest-watch)
ptw -- --cov=. --cov-report=term-missing
```

## Troubleshooting

### Coverage Not Generated

**Problem:** No `.coverage` file created

**Solution:**
```bash
# Ensure pytest-cov is installed
make test-deps

# Check pytest configuration
cat tests/pytest.ini

# Run with explicit coverage
cd tests
pytest -v --cov=. --cov-report=term
```

### Low Coverage Percentage

**Problem:** Coverage below threshold (70%)

**Solution:**
```bash
# Identify uncovered code
make coverage-report

# View detailed HTML report
make coverage-html
make coverage-open

# Add tests for uncovered lines
# Or exclude with: # pragma: no cover
```

### Parallel Coverage Issues

**Problem:** Coverage incomplete with `pytest-xdist`

**Solution:**
```bash
# Ensure parallel mode enabled in .coveragerc
grep "parallel = True" tests/.coveragerc

# Combine coverage data
cd tests
coverage combine
coverage report
```

### Coverage Files Not Found

**Problem:** `coverage.xml` or `htmlcov/` missing

**Solution:**
```bash
# Clean and regenerate
make coverage-clean
make coverage

# Check output directory
ls -la tests/htmlcov/
ls -la tests/coverage.*
```

### CI/CD Coverage Upload Fails

**Problem:** Codecov upload fails in GitHub Actions

**Solution:**
```bash
# Check coverage file exists
- name: Debug Coverage
  run: |
    ls -la tests/coverage.xml
    cat tests/coverage.xml | head -20

# Use correct file path
- uses: codecov/codecov-action@v3
  with:
    file: tests/coverage.xml  # Correct path
    fail_ci_if_error: false    # Don't fail build
```

### Branch Coverage Missing

**Problem:** No branch coverage shown

**Solution:**
```bash
# Enable in .coveragerc
[run]
branch = True

# Verify with explicit flag
pytest --cov=. --cov-branch --cov-report=term-missing
```

## Advanced Usage

### Coverage for Specific Files

```bash
cd tests
pytest test_phase1_predeployment.py \
  --cov=test_phase1_predeployment \
  --cov-report=html
```

### Differential Coverage (New Code Only)

```bash
# Install diff-cover
pip install diff-cover

# Generate diff coverage report
cd tests
diff-cover coverage.xml --compare-branch=main --html-report diff-coverage.html
```

### Coverage with Minimum Threshold

```bash
# Fail if below 70%
cd tests
pytest --cov=. --cov-report=term --cov-fail-under=70
```

### Exclude Specific Tests

```bash
cd tests
pytest --cov=. --ignore=test_phase7_stress.py --cov-report=term
```

## Coverage Goals

### Current Status

- **Phase 1 (Pre-deployment):** Target 95%+
- **Phase 2 (Infrastructure):** Target 85%+
- **Phase 3 (Baseline):** Target 90%+
- **Phase 4 (Service Mesh):** Target 90%+
- **Phase 6 (Comparative):** Target 95%+
- **Phase 7 (Stress):** Target 85%+

### Overall Project Goal

**Minimum:** 70% (enforced)
**Target:** 85%+
**Ideal:** 90%+

## Resources

### Documentation
- [Coverage.py Docs](https://coverage.readthedocs.io/)
- [pytest-cov Docs](https://pytest-cov.readthedocs.io/)
- [Codecov Docs](https://docs.codecov.com/)

### Related Docs
- [TESTING.md](TESTING.md) - Complete testing guide
- [TESTING_QUICK_REFERENCE.md](TESTING_QUICK_REFERENCE.md) - Testing cheat sheet
- [tests/README.md](../tests/README.md) - Test directory guide

## Quick Reference

| Task | Command |
|------|---------|
| Run all tests with coverage | `make coverage` |
| View HTML report | `make coverage-open` |
| View terminal report | `make coverage-report` |
| Generate XML for CI/CD | `make coverage-xml` |
| Phase-specific coverage | `make coverage-phase1` |
| Mesh-specific coverage | `make coverage-istio` |
| Clean coverage files | `make coverage-clean` |
| Combine parallel coverage | `make coverage-combine` |
| Generate coverage badge | `make coverage-badge` |

---

For questions or issues with coverage, please check the [Troubleshooting](#troubleshooting) section or consult the [main testing documentation](TESTING.md).
