.PHONY: help init deploy-infra deploy-workloads test clean destroy lint format type-check quality

# Variables
TERRAFORM_DIR := terraform/oracle-cloud
WORKLOADS_DIR := kubernetes/workloads
BENCHMARKS_DIR := benchmarks/scripts
ANSIBLE_DIR := ansible
TESTS_DIR := tests
PYTHON := python3
PYTEST := pytest
RUFF := ruff
BLACK := black
MYPY := mypy

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init: ## Initialize project dependencies
	@echo "Initializing project..."
	@cd $(TERRAFORM_DIR) && terraform init
	@echo "Installing required tools..."
	@command -v kubectl || (echo "kubectl not found, please install it" && exit 1)
	@command -v ansible || (echo "ansible not found, installing..." && sudo apt-get install -y ansible)
	@echo "Initialization complete!"

validate: ## Validate Terraform configuration
	@echo "Validating Terraform configuration..."
	@cd $(TERRAFORM_DIR) && terraform validate
	@echo "Validation complete!"

plan: ## Plan Terraform infrastructure
	@echo "Planning infrastructure..."
	@cd $(TERRAFORM_DIR) && terraform plan

deploy-infra: ## Deploy infrastructure with Terraform
	@echo "Deploying infrastructure..."
	@cd $(TERRAFORM_DIR) && terraform apply -auto-approve
	@echo "Infrastructure deployed!"
	@cd $(TERRAFORM_DIR) && terraform output

setup-kubectl: ## Configure kubectl to access the cluster
	@echo "Setting up kubectl..."
	@$(TERRAFORM_DIR)/terraform output -raw ssh_to_master
	@echo "SSH into master and copy /home/ubuntu/.kube/config to your local machine"

deploy-workloads: ## Deploy all Kubernetes workloads
	@echo "Deploying workloads..."
	@kubectl apply -f $(WORKLOADS_DIR)/http-service.yaml
	@kubectl apply -f $(WORKLOADS_DIR)/grpc-service.yaml
	@kubectl apply -f $(WORKLOADS_DIR)/websocket-service.yaml
	@kubectl apply -f $(WORKLOADS_DIR)/database-cluster.yaml
	@kubectl apply -f $(WORKLOADS_DIR)/ml-batch-job.yaml
	@echo "Workloads deployed!"

deploy-baseline: ## Deploy baseline workloads (no service mesh)
	@echo "Deploying baseline workloads..."
	@kubectl apply -f $(WORKLOADS_DIR)/baseline-http-service.yaml
	@kubectl apply -f $(WORKLOADS_DIR)/baseline-grpc-service.yaml
	@echo "Baseline workloads deployed!"

deploy-http: ## Deploy only HTTP workload
	@kubectl apply -f $(WORKLOADS_DIR)/http-service.yaml

deploy-grpc: ## Deploy only gRPC workload
	@kubectl apply -f $(WORKLOADS_DIR)/grpc-service.yaml

deploy-websocket: ## Deploy only WebSocket workload
	@kubectl apply -f $(WORKLOADS_DIR)/websocket-service.yaml

deploy-database: ## Deploy only database workload
	@kubectl apply -f $(WORKLOADS_DIR)/database-cluster.yaml

deploy-ml: ## Deploy only ML workload
	@kubectl apply -f $(WORKLOADS_DIR)/ml-batch-job.yaml

install-istio: ## Install Istio service mesh
	@echo "Installing Istio..."
	@ansible-playbook -i $(ANSIBLE_DIR)/inventory $(ANSIBLE_DIR)/playbooks/setup-istio.yml

install-cilium: ## Install Cilium service mesh
	@echo "Installing Cilium..."
	@ansible-playbook -i $(ANSIBLE_DIR)/inventory $(ANSIBLE_DIR)/playbooks/setup-cilium.yml

test-http: ## Run HTTP load test
	@echo "Running HTTP load test..."
	@cd $(BENCHMARKS_DIR) && bash http-load-test.sh

test-grpc: ## Run gRPC load test
	@echo "Running gRPC load test..."
	@cd $(BENCHMARKS_DIR) && bash grpc-test.sh

test-websocket: ## Run WebSocket load test
	@echo "Running WebSocket load test..."
	@cd $(BENCHMARKS_DIR) && bash websocket-test.sh

test-ml: ## Run ML workload test
	@echo "Running ML workload test..."
	@cd $(BENCHMARKS_DIR) && bash ml-workload.sh

test-baseline: ## Run baseline tests (no service mesh)
	@echo "Running baseline tests..."
	@cd $(BENCHMARKS_DIR) && NAMESPACE=baseline-http SERVICE_URL=baseline-http-server.baseline-http.svc.cluster.local MESH_TYPE=baseline bash http-load-test.sh
	@cd $(BENCHMARKS_DIR) && NAMESPACE=baseline-grpc SERVICE_URL=baseline-grpc-server.baseline-grpc.svc.cluster.local:9000 MESH_TYPE=baseline bash grpc-test.sh
	@echo "Baseline tests complete!"

test-all: ## Run all benchmark tests
	@echo "Running all tests..."
	@$(MAKE) test-http
	@$(MAKE) test-grpc
	@$(MAKE) test-websocket
	@$(MAKE) test-ml
	@echo "All tests complete!"

collect-metrics: ## Collect metrics from all services
	@echo "Collecting metrics..."
	@cd $(BENCHMARKS_DIR) && bash collect-metrics.sh

collect-ebpf-metrics: ## Collect eBPF-specific metrics (Cilium)
	@echo "Collecting eBPF metrics..."
	@cd $(BENCHMARKS_DIR) && bash collect-ebpf-metrics.sh

test-network-policies: ## Test network policy performance
	@echo "Testing network policies..."
	@cd $(BENCHMARKS_DIR) && bash test-network-policies.sh

test-cilium-l7: ## Test Cilium L7 traffic management
	@echo "Testing Cilium L7 features..."
	@cd $(BENCHMARKS_DIR) && bash test-cilium-l7.sh

compare-meshes: ## Compare eBPF vs sidecar performance
	@echo "Comparing service mesh performance..."
	@cd $(BENCHMARKS_DIR) && bash compare-ebpf-vs-sidecar.sh

generate-report: ## Generate benchmark report
	@echo "Generating report..."
	@python3 generate-report.py

status: ## Show cluster status
	@echo "=== Cluster Status ==="
	@kubectl get nodes
	@echo ""
	@echo "=== Workload Status ==="
	@kubectl get pods --all-namespaces
	@echo ""
	@echo "=== Services ==="
	@kubectl get services --all-namespaces

clean-workloads: ## Remove all workloads
	@echo "Removing workloads..."
	@kubectl delete -f $(WORKLOADS_DIR)/http-service.yaml --ignore-not-found
	@kubectl delete -f $(WORKLOADS_DIR)/grpc-service.yaml --ignore-not-found
	@kubectl delete -f $(WORKLOADS_DIR)/websocket-service.yaml --ignore-not-found
	@kubectl delete -f $(WORKLOADS_DIR)/database-cluster.yaml --ignore-not-found
	@kubectl delete -f $(WORKLOADS_DIR)/ml-batch-job.yaml --ignore-not-found
	@echo "Workloads removed!"

clean-results: ## Clean benchmark results
	@echo "Cleaning results..."
	@rm -rf benchmarks/results/*
	@echo "Results cleaned!"

destroy: ## Destroy infrastructure
	@echo "WARNING: This will destroy all infrastructure!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		cd $(TERRAFORM_DIR) && terraform destroy; \
	fi

ssh-master: ## SSH into master node
	@cd $(TERRAFORM_DIR) && eval $$(terraform output -raw ssh_to_master)

logs: ## Show logs from benchmark pods
	@kubectl logs -n http-benchmark -l app=http-server --tail=50
	@kubectl logs -n grpc-benchmark -l app=grpc-server --tail=50

watch: ## Watch pod status
	@watch -n 2 kubectl get pods --all-namespaces

# ==============================================================================
# Testing Targets
# ==============================================================================

test-deps: ## Install test dependencies
	@echo "Installing test dependencies..."
	@if command -v uv >/dev/null 2>&1; then \
		echo "Using UV for faster installation..."; \
		uv pip install -r $(TESTS_DIR)/requirements.txt; \
	else \
		echo "UV not found, using pip (install UV with: curl -LsSf https://astral.sh/uv/install.sh | sh)"; \
		$(PYTHON) -m pip install -r $(TESTS_DIR)/requirements.txt; \
	fi
	@echo "Test dependencies installed!"

test-validate: ## Run pre-deployment validation tests (Phase 1)
	@echo "Running pre-deployment validation tests..."
	@cd $(TESTS_DIR) && $(PYTEST) -v -m phase1

test-infra: ## Run infrastructure validation tests (Phase 2)
	@echo "Running infrastructure tests..."
	@cd $(TESTS_DIR) && $(PYTEST) -v -m phase2

test-baseline: ## Run baseline performance tests (Phase 3)
	@echo "Running baseline tests..."
	@cd $(TESTS_DIR) && $(PYTEST) -v -m phase3 --mesh-type=baseline

test-mesh: ## Run service mesh tests (Phase 4)
	@echo "Running service mesh tests..."
	@echo "Usage: make test-mesh MESH_TYPE=<istio|cilium|linkerd>"
	@cd $(TESTS_DIR) && $(PYTEST) -v -m phase4 --mesh-type=$(MESH_TYPE)

test-mesh-istio: ## Run Istio service mesh tests
	@echo "Running Istio tests..."
	@cd $(TESTS_DIR) && $(PYTEST) -v -m phase4 --mesh-type=istio

test-mesh-cilium: ## Run Cilium service mesh tests
	@echo "Running Cilium tests..."
	@cd $(TESTS_DIR) && $(PYTEST) -v -m phase4 --mesh-type=cilium

test-mesh-linkerd: ## Run Linkerd service mesh tests
	@echo "Running Linkerd tests..."
	@cd $(TESTS_DIR) && $(PYTEST) -v -m phase4 --mesh-type=linkerd

test-compare: ## Run comparative analysis tests (Phase 6)
	@echo "Running comparative analysis..."
	@cd $(TESTS_DIR) && $(PYTEST) -v -m phase6

test-stress: ## Run stress tests (Phase 7)
	@echo "Running stress tests..."
	@cd $(TESTS_DIR) && $(PYTEST) -v -m phase7 --mesh-type=$(or $(MESH_TYPE),baseline)

test-quick: ## Run quick tests (exclude slow tests)
	@echo "Running quick tests..."
	@cd $(TESTS_DIR) && $(PYTEST) -v -m "not slow"

test-full: ## Run complete test suite for baseline
	@echo "Running full test suite for baseline..."
	@cd $(TESTS_DIR) && $(PYTHON) run_tests.py --phase=all --mesh-type=baseline

test-full-istio: ## Run complete test suite for Istio
	@echo "Running full test suite for Istio..."
	@cd $(TESTS_DIR) && $(PYTHON) run_tests.py --phase=all --mesh-type=istio

test-full-cilium: ## Run complete test suite for Cilium
	@echo "Running full test suite for Cilium..."
	@cd $(TESTS_DIR) && $(PYTHON) run_tests.py --phase=all --mesh-type=cilium

test-orchestrated: ## Run orchestrated test suite
	@echo "Running orchestrated tests..."
	@echo "Usage: make test-orchestrated MESH_TYPE=<baseline|istio|cilium|linkerd> [PHASE=<phase>]"
	@cd $(TESTS_DIR) && $(PYTHON) run_tests.py \
		--phase=$(or $(PHASE),all) \
		--mesh-type=$(or $(MESH_TYPE),baseline) \
		--test-duration=$(or $(TEST_DURATION),60) \
		--concurrent-connections=$(or $(CONNECTIONS),100)

test-comprehensive: ## Run comprehensive testing workflow (all phases, all meshes)
	@echo "Running comprehensive test suite..."
	@echo "This will run tests for baseline, Istio, and Cilium"
	@echo ""
	@echo "Step 1: Pre-deployment validation..."
	@$(MAKE) test-validate
	@echo ""
	@echo "Step 2: Infrastructure validation..."
	@$(MAKE) test-infra
	@echo ""
	@echo "Step 3: Baseline tests..."
	@$(MAKE) test-full
	@echo ""
	@echo "Step 4: Istio tests..."
	@$(MAKE) test-full-istio
	@echo ""
	@echo "Step 5: Cilium tests..."
	@$(MAKE) test-full-cilium
	@echo ""
	@echo "Step 6: Comparative analysis..."
	@$(MAKE) test-compare
	@echo ""
	@echo "✅ Comprehensive testing complete!"
	@echo "📊 Check benchmarks/results/ for detailed reports"

test-ci: ## Run CI-friendly test suite
	@echo "Running CI test suite..."
	@cd $(TESTS_DIR) && $(PYTEST) -v -m "phase1" \
		--html=../benchmarks/results/ci_report.html \
		--self-contained-html \
		--json-report \
		--json-report-file=../benchmarks/results/ci_report.json

test-report: ## Generate test report
	@echo "Generating test report..."
	@$(PYTHON) generate-report.py
	@echo "Report generated in benchmarks/results/report.html"

test-clean: ## Clean test results
	@echo "Cleaning test results..."
	@rm -rf $(TESTS_DIR)/.pytest_cache
	@rm -rf $(TESTS_DIR)/__pycache__
	@rm -rf $(TESTS_DIR)/**/__pycache__
	@rm -f $(TESTS_DIR)/*.pyc
	@echo "Test artifacts cleaned!"

# ==============================================================================
# Coverage Targets
# ==============================================================================

coverage: ## Run tests with coverage report
	@echo "Running tests with coverage..."
	@cd $(TESTS_DIR) && $(PYTEST) -v --cov=. --cov-report=html --cov-report=term-missing --cov-report=json --cov-report=xml

coverage-html: ## Generate HTML coverage report
	@echo "Generating HTML coverage report..."
	@cd $(TESTS_DIR) && $(PYTEST) -v --cov=. --cov-report=html
	@echo "Coverage report generated: $(TESTS_DIR)/htmlcov/index.html"
	@echo "Open with: xdg-open $(TESTS_DIR)/htmlcov/index.html"

coverage-report: ## Show coverage report in terminal
	@echo "Showing coverage report..."
	@cd $(TESTS_DIR) && $(PYTEST) -v --cov=. --cov-report=term-missing

coverage-xml: ## Generate XML coverage report (for CI/CD)
	@echo "Generating XML coverage report..."
	@cd $(TESTS_DIR) && $(PYTEST) -v --cov=. --cov-report=xml
	@echo "Coverage XML generated: $(TESTS_DIR)/coverage.xml"

coverage-json: ## Generate JSON coverage report
	@echo "Generating JSON coverage report..."
	@cd $(TESTS_DIR) && $(PYTEST) -v --cov=. --cov-report=json
	@echo "Coverage JSON generated: $(TESTS_DIR)/coverage.json"

coverage-phase1: ## Run Phase 1 tests with coverage
	@echo "Running Phase 1 tests with coverage..."
	@cd $(TESTS_DIR) && $(PYTEST) -v -m phase1 --cov=. --cov-report=html --cov-report=term-missing

coverage-phase2: ## Run Phase 2 tests with coverage
	@echo "Running Phase 2 tests with coverage..."
	@cd $(TESTS_DIR) && $(PYTEST) -v -m phase2 --cov=. --cov-report=html --cov-report=term-missing

coverage-phase3: ## Run Phase 3 tests with coverage
	@echo "Running Phase 3 tests with coverage..."
	@cd $(TESTS_DIR) && $(PYTEST) -v -m phase3 --cov=. --cov-report=html --cov-report=term-missing

coverage-phase4: ## Run Phase 4 tests with coverage
	@echo "Running Phase 4 tests with coverage..."
	@cd $(TESTS_DIR) && $(PYTEST) -v -m phase4 --cov=. --cov-report=html --cov-report=term-missing --mesh-type=$(or $(MESH_TYPE),baseline)

coverage-phase6: ## Run Phase 6 tests with coverage
	@echo "Running Phase 6 tests with coverage..."
	@cd $(TESTS_DIR) && $(PYTEST) -v -m phase6 --cov=. --cov-report=html --cov-report=term-missing

coverage-phase7: ## Run Phase 7 tests with coverage
	@echo "Running Phase 7 tests with coverage..."
	@cd $(TESTS_DIR) && $(PYTEST) -v -m phase7 --cov=. --cov-report=html --cov-report=term-missing

coverage-baseline: ## Run baseline tests with coverage
	@echo "Running baseline tests with coverage..."
	@cd $(TESTS_DIR) && $(PYTEST) -v --mesh-type=baseline --cov=. --cov-report=html --cov-report=term-missing

coverage-istio: ## Run Istio tests with coverage
	@echo "Running Istio tests with coverage..."
	@cd $(TESTS_DIR) && $(PYTEST) -v -m phase4 --mesh-type=istio --cov=. --cov-report=html --cov-report=term-missing

coverage-cilium: ## Run Cilium tests with coverage
	@echo "Running Cilium tests with coverage..."
	@cd $(TESTS_DIR) && $(PYTEST) -v -m phase4 --mesh-type=cilium --cov=. --cov-report=html --cov-report=term-missing

coverage-open: ## Open HTML coverage report in browser
	@echo "Opening coverage report..."
	@xdg-open $(TESTS_DIR)/htmlcov/index.html || open $(TESTS_DIR)/htmlcov/index.html || echo "Please open $(TESTS_DIR)/htmlcov/index.html manually"

coverage-clean: ## Clean coverage reports
	@echo "Cleaning coverage reports..."
	@rm -rf $(TESTS_DIR)/htmlcov
	@rm -f $(TESTS_DIR)/.coverage
	@rm -f $(TESTS_DIR)/.coverage.*
	@rm -f $(TESTS_DIR)/coverage.xml
	@rm -f $(TESTS_DIR)/coverage.json
	@echo "Coverage reports cleaned!"

coverage-badge: ## Generate coverage badge
	@echo "Generating coverage badge..."
	@cd $(TESTS_DIR) && coverage-badge -o ../docs/coverage.svg -f
	@echo "Coverage badge generated: docs/coverage.svg"

coverage-combine: ## Combine coverage data from parallel runs
	@echo "Combining coverage data..."
	@cd $(TESTS_DIR) && coverage combine
	@cd $(TESTS_DIR) && coverage report
	@echo "Coverage data combined!"

# ==============================================================================
# Code Quality Targets
# ==============================================================================

quality-deps: ## Install code quality tools
	@echo "Installing code quality dependencies..."
	@if command -v uv >/dev/null 2>&1; then \
		echo "Using UV for faster installation..."; \
		uv pip install ruff black mypy pre-commit; \
	else \
		echo "UV not found, using pip"; \
		$(PYTHON) -m pip install ruff black mypy pre-commit; \
	fi
	@echo "Code quality tools installed!"

lint: ## Run ruff linter
	@echo "Running ruff linter..."
	@$(RUFF) check . --config=pyproject.toml

lint-fix: ## Run ruff linter with auto-fix
	@echo "Running ruff linter with auto-fix..."
	@$(RUFF) check . --fix --config=pyproject.toml

format: ## Run black formatter
	@echo "Running black formatter..."
	@$(BLACK) . --config=pyproject.toml

format-check: ## Check formatting without making changes
	@echo "Checking code formatting..."
	@$(BLACK) . --check --config=pyproject.toml

type-check: ## Run mypy type checking
	@echo "Running mypy type checker..."
	@$(MYPY) tests/ generate-report.py --config-file=pyproject.toml

quality: ## Run all code quality checks (lint, format, type-check)
	@echo "Running all code quality checks..."
	@$(MAKE) lint
	@$(MAKE) format-check
	@$(MAKE) type-check
	@echo "✅ All code quality checks passed!"

quality-fix: ## Fix all auto-fixable issues (lint + format)
	@echo "Fixing all auto-fixable issues..."
	@$(MAKE) lint-fix
	@$(MAKE) format
	@echo "✅ Code quality issues fixed!"

pre-commit-install: ## Install pre-commit hooks
	@echo "Installing pre-commit hooks..."
	@pre-commit install
	@pre-commit install --hook-type commit-msg
	@echo "✅ Pre-commit hooks installed!"

pre-commit-run: ## Run pre-commit hooks on all files
	@echo "Running pre-commit hooks on all files..."
	@pre-commit run --all-files

pre-commit-update: ## Update pre-commit hooks to latest versions
	@echo "Updating pre-commit hooks..."
	@pre-commit autoupdate

shellcheck: ## Run shellcheck on shell scripts
	@echo "Running shellcheck on shell scripts..."
	@find benchmarks/scripts -name "*.sh" -type f -exec shellcheck {} \;
	@find ebpf-probes -name "*.sh" -type f -exec shellcheck {} \; 2>/dev/null || true

yamllint: ## Run yamllint on YAML files
	@echo "Running yamllint on YAML files..."
	@yamllint -c .yamllint.yaml .

ansible-lint: ## Run ansible-lint on Ansible playbooks
	@echo "Running ansible-lint on Ansible playbooks..."
	@ansible-lint ansible/playbooks/

quality-all: ## Run all linters (Python, shell, YAML, Ansible)
	@echo "Running all linters..."
	@$(MAKE) lint
	@$(MAKE) format-check
	@$(MAKE) type-check
	@$(MAKE) shellcheck || echo "⚠️  Shellcheck found issues"
	@$(MAKE) yamllint || echo "⚠️  YAML linting found issues"
	@$(MAKE) ansible-lint || echo "⚠️  Ansible linting found issues"
	@echo "✅ All linters completed!"

quality-clean: ## Clean code quality artifacts
	@echo "Cleaning code quality artifacts..."
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.pyc" -delete 2>/dev/null || true
	@find . -type d -name ".ruff_cache" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name ".mypy_cache" -exec rm -rf {} + 2>/dev/null || true
	@echo "✅ Code quality artifacts cleaned!"
