# Terraform Configuration for Oracle Cloud

This directory contains Terraform configuration for deploying the Service Mesh Benchmark infrastructure to Oracle Cloud Infrastructure (OCI) Free Tier.

## Quick Start

```bash
# 1. Copy and configure variables
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars  # Add your OCI credentials

# 2. Initialize Terraform
terraform init

# 3. Review planned changes
terraform plan

# 4. Deploy infrastructure
terraform apply

# 5. Note the public IP from outputs
terraform output instance_public_ip
```

## What Gets Created

- **Compute Instance**: VM.Standard.E2.1.Micro (Free Tier)
- **VCN**: Virtual Cloud Network with public subnet
- **Security List**: Firewall rules for all application ports
- **Internet Gateway**: Public internet access
- **Public IP**: Static public IP address

## Free Tier Resources

This configuration uses OCI Always Free resources:
- 1x VM.Standard.E2.1.Micro instance (1 OCPU, 1GB RAM)
- 50GB boot volume
- 1x VCN
- Public IP address

## Files

- `main.tf`: Main infrastructure configuration
- `variables.tf`: Input variable definitions
- `outputs.tf`: Output values after deployment
- `cloud-init.yaml`: Instance initialization script
- `inventory.tpl`: Ansible inventory template
- `terraform.tfvars.example`: Example configuration file

## Next Steps

After infrastructure is deployed:

1. **Test SSH connection**:
   ```bash
   ssh -i ~/.ssh/oci_benchmark_key ubuntu@<PUBLIC_IP>
   ```

2. **Run Ansible playbooks**:
   ```bash
   cd ../ansible
   ansible-playbook -i inventory/hosts.yml playbooks/setup-server.yml
   ansible-playbook -i inventory/hosts.yml playbooks/deploy-app.yml
   ```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

## Documentation

See [../docs/TERRAFORM_ANSIBLE_DEPLOYMENT.md](../docs/TERRAFORM_ANSIBLE_DEPLOYMENT.md) for complete documentation.
