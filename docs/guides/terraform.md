# Terraform Configuration for Oracle Cloud

This guide covers two Terraform deployment options for Oracle Cloud Infrastructure (OCI):

## Deployment Options

### 1. Single Instance Deployment (`infrastructure/terraform/single-instance/`)
Simple single-VM deployment with Ansible integration. Ideal for basic testing and development.

### 2. Kubernetes Cluster Deployment (`infrastructure/terraform/oracle-cloud/`)
Full Kubernetes cluster with master and worker nodes, plus load balancer. For production-grade benchmarking.

---

## Single Instance Deployment

Located in `infrastructure/terraform/single-instance/`. This configuration deploys a single instance and integrates with Ansible for application setup.

### Quick Start

```bash
cd infrastructure/terraform/single-instance

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
   cd infrastructure/ansible
   ansible-playbook -i inventory/hosts.yml playbooks/setup-server.yml
   ansible-playbook -i inventory/hosts.yml playbooks/deploy-app.yml
   ```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

## Documentation

See [terraform-ansible-deployment.md](terraform-ansible-deployment.md) for complete documentation.
