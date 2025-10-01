#!/bin/bash
set -e

echo "Setting up Service Mesh Benchmark development environment..."

# Make scripts executable
chmod +x benchmarks/scripts/*.sh
chmod +x generate-report.py

# Install Python dependencies
pip3 install --user requests pandas matplotlib

echo "Development environment setup complete!"
echo ""
echo "Quick start:"
echo "  1. Configure Terraform: cp terraform/oracle-cloud/terraform.tfvars.example terraform/oracle-cloud/terraform.tfvars"
echo "  2. Deploy infrastructure: make deploy-infra"
echo "  3. Deploy workloads: make deploy-workloads"
echo "  4. Run tests: make test-all"
echo "  5. Generate report: make generate-report"
echo ""
echo "For more information, see README.md"
