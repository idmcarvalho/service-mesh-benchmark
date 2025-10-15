.PHONY: help init deploy-infra deploy-workloads test clean destroy

# Variables
TERRAFORM_DIR := terraform/oracle-cloud
WORKLOADS_DIR := kubernetes/workloads
BENCHMARKS_DIR := benchmarks/scripts
ANSIBLE_DIR := ansible
TESTS_DIR := tests
PYTHON := python3
PYTEST := pytest

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
