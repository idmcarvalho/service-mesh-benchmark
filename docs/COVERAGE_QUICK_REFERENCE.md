# Coverage Quick Reference

Quick reference guide for code coverage commands and workflows.

## One-Liners

```bash
# Run all tests with coverage
make coverage

# View HTML report
make coverage-open

# Terminal report with missing lines
make coverage-report

# Clean coverage artifacts
make coverage-clean
```

## Common Workflows

### Development Workflow

```bash
# 1. Make changes to tests
vim tests/test_phase1_predeployment.py

# 2. Run coverage for that phase
make coverage-phase1

# 3. View results
make coverage-open

# 4. Repeat until satisfied
```

### Pre-Commit Workflow

```bash
# Run all tests with coverage
make coverage

# Check threshold (must be ≥70%)
make coverage-report | grep "TOTAL"

# View detailed report if needed
make coverage-open

# Clean up before commit
make coverage-clean
```

### CI/CD Workflow

```bash
# Local simulation of CI
make test-deps
make coverage-xml
cat tests/coverage.xml

# Check it matches CI expectations
```

## Phase-Specific Commands

```bash
make coverage-phase1    # Pre-deployment (fast)
make coverage-phase2    # Infrastructure
make coverage-phase3    # Baseline
make coverage-phase4    # Service mesh
make coverage-phase6    # Comparative
make coverage-phase7    # Stress tests
```

## Mesh-Specific Commands

```bash
make coverage-baseline  # No mesh
make coverage-istio     # Istio tests
make coverage-cilium    # Cilium tests
```

## Report Formats

```bash
make coverage-html      # HTML report → tests/htmlcov/index.html
make coverage-report    # Terminal output
make coverage-xml       # XML → tests/coverage.xml (CI/CD)
make coverage-json      # JSON → tests/coverage.json
```

## Direct pytest Commands

```bash
cd tests

# All tests with coverage
pytest -v --cov=. --cov-report=term-missing

# Specific phase
pytest -v -m phase1 --cov=. --cov-report=html

# Specific file
pytest test_phase1_predeployment.py -v --cov=. --cov-report=term

# Specific test
pytest test_phase1_predeployment.py::test_terraform_exists -v --cov=. --cov-report=term-missing

# With minimum threshold
pytest -v --cov=. --cov-fail-under=70
```

## Interpreting Output

### Terminal Report
```
Name                               Stmts   Miss  Cover   Missing
----------------------------------------------------------------
conftest.py                          150     10    93%   45-48, 203
test_phase1_predeployment.py         320     25    92%   156-162
----------------------------------------------------------------
TOTAL                               1000     85    92%
```

- **Stmts**: Total statements
- **Miss**: Statements not executed
- **Cover**: Coverage percentage
- **Missing**: Line numbers not covered

### Coverage Thresholds

| Status | Coverage | Indicator |
|--------|----------|-----------|
| Excellent | 90-100% | 🟢🟢🟢 |
| Good | 80-89% | 🟢🟢 |
| Acceptable | 70-79% | 🟢 |
| Below Threshold | <70% | 🔴 |

## Troubleshooting

### No coverage data
```bash
# Reinstall dependencies
make test-deps

# Check configuration
cat tests/pytest.ini | grep cov
cat tests/.coveragerc
```

### Coverage too low
```bash
# Find low-coverage files
make coverage-report | sort -k4 -n

# View in browser
make coverage-html
make coverage-open
```

### Parallel test issues
```bash
# Combine coverage data
make coverage-combine

# Or manually
cd tests
coverage combine
coverage report
```

### HTML report not opening
```bash
# Manual open
xdg-open tests/htmlcov/index.html    # Linux
open tests/htmlcov/index.html        # macOS
start tests/htmlcov/index.html       # Windows
```

## Configuration Files

- `tests/.coveragerc` - Coverage configuration
- `tests/pytest.ini` - Pytest coverage settings
- `.gitignore` - Excludes coverage artifacts

## CI/CD Integration

### GitHub Actions
- Runs automatically on push/PR
- Uploads to Codecov
- Comments on PRs with coverage report
- Artifacts include `htmlcov/` and `coverage.xml`

### View CI Coverage
1. Check GitHub Actions run
2. Download artifacts
3. Extract and open `htmlcov/index.html`

## Advanced Usage

### Coverage for new code only
```bash
pip install diff-cover
cd tests
diff-cover coverage.xml --compare-branch=main
```

### Coverage with parallel execution
```bash
cd tests
pytest -v -n auto --cov=. --cov-append
coverage combine
coverage report
```

### Generate coverage badge
```bash
pip install coverage-badge
make coverage-badge
# Output: docs/coverage.svg
```

## File Locations

```
tests/
├── .coveragerc          # Coverage config
├── pytest.ini           # Pytest config with coverage
├── .coverage            # Coverage data (binary)
├── coverage.xml         # XML report (CI/CD)
├── coverage.json        # JSON report
└── htmlcov/             # HTML report directory
    └── index.html       # Main HTML report
```

## Coverage Exclusions

Exclude specific lines from coverage:

```python
def example():
    try:
        risky_operation()
    except Exception:
        pass  # pragma: no cover

if __name__ == "__main__":  # pragma: no cover
    main()
```

## Quick Tips

1. **Run coverage regularly** - Don't wait for CI
2. **Focus on critical code** - Not everything needs 100%
3. **Use HTML reports** - Much easier to navigate
4. **Check missing lines** - Use `--cov-report=term-missing`
5. **Clean artifacts** - Run `make coverage-clean` periodically
6. **Parallel tests** - Remember to combine coverage data
7. **CI/CD first** - Ensure XML format works for CI

## Getting Help

- Full documentation: [COVERAGE.md](COVERAGE.md)
- Testing guide: [TESTING.md](TESTING.md)
- Tests README: [../tests/README.md](../tests/README.md)

## Coverage Goals

| Component | Minimum | Target |
|-----------|---------|--------|
| Phase 1 | 90% | 95% |
| Phase 2 | 80% | 85% |
| Phase 3 | 85% | 90% |
| Phase 4 | 85% | 90% |
| Phase 6 | 90% | 95% |
| Phase 7 | 80% | 85% |
| **Overall** | **70%** | **85%** |

---

**Remember:** Coverage is a tool, not a goal. Focus on meaningful tests, not just coverage numbers!
