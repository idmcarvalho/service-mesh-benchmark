.PHONY: help setup build-all clean install-deps

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

install-deps: ## Install Rust and eBPF development dependencies
	@echo "Installing Rust toolchain..."
	@command -v rustc || curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
	@echo "Installing bpf-linker..."
	@cargo install bpf-linker || true
	@echo "Adding eBPF target..."
	@rustup target add bpfel-unknown-none
	@echo "Installing system dependencies..."
	@sudo apt-get update && sudo apt-get install -y llvm clang libbpf-dev linux-headers-$(shell uname -r)
	@echo "Dependencies installed!"

setup: ## Setup development environment
	@echo "Setting up eBPF probe development environment..."
	@$(MAKE) install-deps
	@echo "Verifying setup..."
	@rustc --version
	@cargo --version
	@llvm-config --version
	@echo "Setup complete!"

build-latency-probe: ## Build latency probe
	@echo "Building latency probe..."
	@cd latency-probe/latency-probe-ebpf && cargo build --release --target=bpfel-unknown-none
	@cd latency-probe/latency-probe-userspace && cargo build --release
	@echo "Latency probe built successfully!"

build-packet-drop-probe: ## Build packet drop probe
	@echo "Building packet drop probe..."
	@cd packet-drop-probe/packet-drop-ebpf && cargo build --release --target=bpfel-unknown-none
	@cd packet-drop-probe/packet-drop-userspace && cargo build --release
	@echo "Packet drop probe built successfully!"

build-connection-tracker: ## Build connection tracker
	@echo "Building connection tracker..."
	@cd connection-tracker/connection-tracker-ebpf && cargo build --release --target=bpfel-unknown-none
	@cd connection-tracker/connection-tracker-userspace && cargo build --release
	@echo "Connection tracker built successfully!"

build-all: ## Build all eBPF probes
	@echo "Building all eBPF probes..."
	@$(MAKE) build-latency-probe || echo "Latency probe build failed"
	@$(MAKE) build-packet-drop-probe || echo "Packet drop probe build failed"
	@$(MAKE) build-connection-tracker || echo "Connection tracker build failed"
	@echo "All probes built!"

test: ## Run tests for all probes
	@echo "Running tests..."
	@cd latency-probe/latency-probe-userspace && cargo test
	@echo "Tests complete!"

clean: ## Clean build artifacts
	@echo "Cleaning build artifacts..."
	@find . -name target -type d -exec rm -rf {} + 2>/dev/null || true
	@find . -name Cargo.lock -type f -delete 2>/dev/null || true
	@echo "Clean complete!"

check-btf: ## Check if BTF is available
	@echo "Checking BTF support..."
	@if [ -f /sys/kernel/btf/vmlinux ]; then \
		echo "✓ BTF is available"; \
		ls -lh /sys/kernel/btf/vmlinux; \
	else \
		echo "✗ BTF is NOT available - eBPF probes will not work"; \
		echo "  Install a kernel with BTF support (>= 5.10)"; \
		exit 1; \
	fi

check-kernel: ## Check kernel version
	@echo "Checking kernel version..."
	@KERNEL_VERSION=$$(uname -r | cut -d. -f1-2); \
	REQUIRED=5.10; \
	if [ "$$(printf '%s\n' "$$REQUIRED" "$$KERNEL_VERSION" | sort -V | head -n1)" = "$$REQUIRED" ]; then \
		echo "✓ Kernel version $$KERNEL_VERSION is supported"; \
	else \
		echo "✗ Kernel version $$KERNEL_VERSION is too old"; \
		echo "  Minimum required: $$REQUIRED"; \
		exit 1; \
	fi

verify: ## Verify environment for eBPF development
	@echo "Verifying eBPF development environment..."
	@$(MAKE) check-kernel
	@$(MAKE) check-btf
	@command -v rustc || (echo "✗ Rust not installed" && exit 1)
	@command -v llvm-config || (echo "✗ LLVM not installed" && exit 1)
	@rustup target list | grep -q bpfel-unknown-none && echo "✓ eBPF target installed" || (echo "✗ eBPF target not installed" && exit 1)
	@echo "✓ Environment verified!"
