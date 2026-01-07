# Poetry Setup & Migration Guide

This project uses [Poetry](https://python-poetry.org/) for dependency management with automatic lock file generation and hash verification.

## Why Poetry?

- **Lock files**: `poetry.lock` ensures reproducible builds across environments
- **Hash verification**: Automatic integrity checks for all dependencies
- **Dependency groups**: Separate test, dev, and production dependencies
- **CVE scanning**: Integrated with pip-audit and safety for security scanning
- **Faster CI**: Cached virtual environments speed up builds

## Installation

### Install Poetry

```bash
# Via pipx (recommended)
pipx install poetry

# Or via official installer
curl -sSL https://install.python-poetry.org | python3 -
```

### Configure Poetry (optional)

```bash
# Create virtualenvs in project directory
poetry config virtualenvs.in-project true
```

## Initial Setup

### 1. Generate the Lock File

```bash
# From project root
poetry lock

# This creates poetry.lock with all dependency versions and hashes
```

### 2. Install Dependencies

```bash
# Install all dependencies (including test and dev)
poetry install

# Or install only production dependencies
poetry install --without test,dev
```

## Daily Usage

### Adding Dependencies

```bash
# Add a production dependency
poetry add fastapi

# Add a dev dependency
poetry add --group dev black

# Add a test dependency
poetry add --group test pytest
```

### Updating Dependencies

```bash
# Update all dependencies
poetry update

# Update specific package
poetry update fastapi

# Show outdated packages
poetry show --outdated
```

### Running Commands

```bash
# Run pytest
poetry run pytest

# Run ruff
poetry run ruff check .

# Activate the virtual environment
poetry shell
```

## Dependency Groups

Our project uses three dependency groups:

1. **Main dependencies** (`[tool.poetry.dependencies]`)
   - Core runtime dependencies
   - API framework (FastAPI, uvicorn)
   - Kubernetes client, etc.

2. **Test dependencies** (`[tool.poetry.group.test.dependencies]`)
   - pytest and plugins
   - Test coverage tools

3. **Dev dependencies** (`[tool.poetry.group.dev.dependencies]`)
   - Linters (ruff, black)
   - Type checkers (mypy)
   - Security scanners (pip-audit, safety)
   - Pre-commit hooks

## Security Scanning

### Local Scanning

```bash
# Install with dev dependencies (includes pip-audit and safety)
poetry install --with dev

# Run pip-audit
poetry run pip-audit

# Run safety check
poetry run safety check
```

### CI/CD Integration

Our CI automatically:
1. Exports poetry.lock to requirements.txt format
2. Scans with pip-audit (OSV/PyPI databases)
3. Scans with safety (Safety DB)
4. Fails the build if CVEs are found

## Migration from requirements.txt

The old requirements files have been migrated:

- `src/api/requirements.txt` → `[tool.poetry.dependencies]`
- `src/tests/requirements.txt` → `[tool.poetry.group.test.dependencies]`

### Legacy Files

You can keep the old requirements.txt files for reference or regenerate them:

```bash
# Export to requirements.txt format (without hashes)
poetry export -f requirements.txt --output requirements.txt

# Export with hashes for added security
poetry export -f requirements.txt --output requirements.txt --with-hashes

# Export specific groups
poetry export -f requirements.txt --only main --output requirements-main.txt
poetry export -f requirements.txt --with test --output requirements-test.txt
```

## Troubleshooting

### Lock File Out of Sync

```bash
# If pyproject.toml was modified manually
poetry lock --no-update  # Update lock without upgrading dependencies
```

### Cache Issues

```bash
# Clear Poetry cache
poetry cache clear pypi --all
```

### Dependency Resolution Conflicts

```bash
# See why a package is required
poetry show --tree

# Show package details
poetry show fastapi
```

## Best Practices

1. **Always commit `poetry.lock`** - Ensures everyone uses the same versions
2. **Update regularly** - Run `poetry update` weekly to get security patches
3. **Review updates** - Check `poetry show --outdated` before updating
4. **Pin critical versions** - Use `^` for compatible versions, `==` for exact pins
5. **Run security scans** - Use `poetry run pip-audit` before releases

## CI/CD Workflows

### GitHub Actions Cache

Our workflows cache the virtual environment based on `poetry.lock`:

```yaml
- name: Load cached venv
  uses: actions/cache@v3
  with:
    path: .venv
    key: venv-${{ runner.os }}-${{ hashFiles('**/poetry.lock') }}
```

This speeds up CI by ~2-3 minutes per run!

## Resources

- [Poetry Documentation](https://python-poetry.org/docs/)
- [Poetry Commands](https://python-poetry.org/docs/cli/)
- [Dependency Specification](https://python-poetry.org/docs/dependency-specification/)
