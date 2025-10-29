# Development Environment

This directory contains development environment configurations and build tools.

## Directory Structure

### [.devcontainer/](.devcontainer/)
VS Code Dev Container configuration:
- `Dockerfile` - Development container image
- `devcontainer.json` - VS Code dev container settings
- `scripts/` - Post-creation and setup scripts
  - `post-create.sh` - Run after container creation
  - `install-istio.sh` - Install Istio for local testing
  - `install-cilium.sh` - Install Cilium for local testing
  - `run-benchmarks.sh` - Local benchmark execution

### Root Files
- `Makefile` - Build and automation targets (copy of root Makefile)
- `pyproject.toml` - Python project configuration (copy)

## Getting Started

### Using Dev Container (Recommended)

1. **Prerequisites**:
   - Docker Desktop
   - Visual Studio Code
   - Dev Containers extension

2. **Open in Container**:
   ```bash
   # From VS Code
   - Open the repository
   - Press F1 -> "Dev Containers: Reopen in Container"
   ```

3. **Wait for Setup**:
   The container will:
   - Build the development image
   - Install all dependencies
   - Run post-creation scripts
   - Configure development tools

### Local Development (Without Container)

1. **Install Dependencies**:
   ```bash
   # Python dependencies
   pip install -e ".[dev]"

   # Rust/eBPF dependencies
   rustup install stable
   cargo install bpf-linker

   # Kubernetes tools
   # See infrastructure/README.md
   ```

2. **Set Up Environment**:
   ```bash
   cp config/templates/.env.example .env
   # Edit .env with your values
   ```

3. **Run Development Services**:
   ```bash
   docker-compose -f config/local/docker-compose.yml up
   ```

## Development Workflow

### Running Tests
```bash
# All tests
make test

# Specific phase
pytest src/tests/phase1_predeployment/

# With coverage
make test-coverage
```

### Code Quality
```bash
# Format code
make format

# Lint
make lint

# Type check
make type-check

# All quality checks
make check
```

### Building Components

#### API Service
```bash
# Development mode (hot reload)
make dev-api

# Production build
make build-api
```

#### eBPF Probes
```bash
# Build probes
cd src/probes
cargo build --release

# Or use Makefile
make build-ebpf
```

#### Docker Images
```bash
# Build all images
make build-images

# Build specific image
docker build -t benchmark-api:dev workloads/docker/api/
```

### Local Benchmarking
```bash
# Start local cluster (kind or minikube)
make local-cluster

# Deploy workloads
make deploy-workloads

# Run benchmarks
make run-benchmarks
```

## Makefile Targets

Common targets from the root Makefile:

| Target | Description |
|--------|-------------|
| `make help` | Show all available targets |
| `make test` | Run all tests |
| `make lint` | Run linters (ruff, mypy, shellcheck) |
| `make format` | Format code (ruff, black) |
| `make build` | Build all components |
| `make dev` | Start development environment |
| `make clean` | Clean build artifacts |
| `make deploy` | Deploy to cluster |
| `make benchmark` | Run benchmarks |

## Pre-commit Hooks

Git hooks are configured in `config/local/.pre-commit-config.yaml`:

```bash
# Install hooks
pre-commit install

# Run manually
pre-commit run --all-files
```

Hooks include:
- Code formatting (ruff, black)
- Linting (ruff, mypy, shellcheck)
- YAML validation
- Security checks (bandit)
- Large file prevention

## IDE Configuration

### VS Code
The dev container includes:
- Python extension with type checking
- Rust analyzer
- Kubernetes extension
- Docker extension
- GitLens
- YAML extension

### PyCharm/IntelliJ
Import the project and:
1. Mark `src/` as Sources Root
2. Configure Python interpreter from `pyproject.toml`
3. Enable pytest as test runner
4. Configure Rust plugin for `src/probes/`

## Troubleshooting

### Container Issues
```bash
# Rebuild container
# From VS Code: F1 -> "Dev Containers: Rebuild Container"

# Or manually:
docker-compose -f develop/.devcontainer/docker-compose.yml build
```

### Python Dependencies
```bash
# Update dependencies
pip install --upgrade -e ".[dev]"

# Clear cache
pip cache purge
rm -rf __pycache__ .pytest_cache
```

### eBPF Build Issues
```bash
# Install kernel headers
sudo apt-get install linux-headers-$(uname -r)

# Rebuild probes
cd src/probes
cargo clean
cargo build
```

### Permission Issues
```bash
# Fix file permissions
sudo chown -R $USER:$USER .

# Docker socket access
sudo usermod -aG docker $USER
```

## Environment Variables

Copy `config/templates/.env.example` to `.env` and configure:

```bash
# Required
DATABASE_URL=postgresql://user:pass@localhost:5432/benchmark
KUBECONFIG=/path/to/kubeconfig

# Optional
LOG_LEVEL=DEBUG
API_WORKERS=1
EBPF_ENABLED=true
```

## Best Practices

1. **Use Dev Container** - Ensures consistent environment
2. **Run Tests Before Commit** - Pre-commit hooks help catch issues
3. **Keep Dependencies Updated** - Regular `pip install --upgrade`
4. **Clean Build Artifacts** - `make clean` before major changes
5. **Document Changes** - Update relevant README files
6. **Follow Style Guide** - Let formatters handle style

## Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines on:
- Code style
- Commit messages
- Pull request process
- Testing requirements
