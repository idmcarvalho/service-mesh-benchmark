.PHONY: help init deploy-infra deploy-workloads test clean destroy

# Variables
TERRAFORM_DIR := terraform/oracle-cloud
WORKLOADS_DIR := kubernetes/workloads
BENCHMARKS_DIR := benchmarks/scripts
ANSIBLE_DIR := ansible

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

test-ml: ## Run ML workload test
	@echo "Running ML workload test..."
	@cd $(BENCHMARKS_DIR) && bash ml-workload.sh

test-all: ## Run all benchmark tests
	@echo "Running all tests..."
	@$(MAKE) test-http
	@$(MAKE) test-grpc
	@$(MAKE) test-ml
	@echo "All tests complete!"

collect-metrics: ## Collect metrics from all services
	@echo "Collecting metrics..."
	@cd $(BENCHMARKS_DIR) && bash collect-metrics.sh

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
