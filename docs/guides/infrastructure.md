# Infrastructure as Code

This directory contains all infrastructure provisioning and configuration management code.

## Directory Structure

### [terraform/](terraform/)
Infrastructure provisioning using Terraform:
- `oracle-cloud/` - Oracle Cloud Infrastructure (OCI) provider configuration
  - Provisions 3-node Kubernetes cluster (1 master, 2 workers)
  - Configures VCN, subnets, and security groups
  - Sets up load balancer for service exposure
  - ARM-based instances (Free Tier compatible)

**Usage**:
```bash
cd infrastructure/terraform/oracle-cloud
terraform init
terraform plan
terraform apply
```

**Required Configuration**:
Copy `config/templates/terraform.tfvars.example` to `terraform.tfvars` and fill in your OCI credentials.

### [ansible/](ansible/)
Configuration management and application deployment:
- `playbooks/` - Ansible playbooks for service mesh setup
  - `setup-istio.yml` - Istio control plane installation
  - `setup-cilium.yml` - Cilium CNI and service mesh setup
  - `setup-consul.yml` - HashiCorp Consul service mesh
  - `deploy-workloads.yml` - Deploy benchmark workloads

**Usage**:
```bash
cd infrastructure/ansible
ansible-playbook -i inventory/hosts.ini playbooks/setup-istio.yml
```

**Required Configuration**:
Copy `config/templates/ansible-inventory.ini.example` to `inventory/hosts.ini` and update with your cluster nodes.

## Deployment Workflow

1. **Provision Infrastructure** (Terraform):
   ```bash
   cd infrastructure/terraform/oracle-cloud
   terraform apply
   ```

2. **Configure Kubernetes Cluster** (Ansible):
   ```bash
   cd infrastructure/ansible
   ansible-playbook playbooks/setup-cluster.yml
   ```

3. **Install Service Mesh** (Ansible):
   ```bash
   # Choose one:
   ansible-playbook playbooks/setup-istio.yml
   ansible-playbook playbooks/setup-cilium.yml
   ansible-playbook playbooks/setup-consul.yml
   ```

4. **Deploy Workloads** (Kubernetes):
   ```bash
   kubectl apply -f workloads/kubernetes/
   ```

## Resource Sizing

**Oracle Cloud Free Tier Configuration**:
- Master Node: 2 OCPUs, 12GB RAM
- Worker Nodes: 1 OCPU, 6GB RAM each (x2)
- Total: 4 OCPUs, 24GB RAM
- Storage: 200GB block storage
- Region: us-ashburn-1 (configurable)

## Security Considerations

- All nodes use security groups with minimal required ports
- SSH access restricted to specific IP ranges
- TLS enabled for all service mesh communication
- RBAC configured for workload isolation
- Network policies enforced at Kubernetes level

## Troubleshooting

### Terraform Issues
- **Authentication failures**: Verify OCI credentials in `terraform.tfvars`
- **Resource limits**: Check Free Tier quotas in OCI console
- **State conflicts**: Use remote backend for team collaboration

### Ansible Issues
- **Connection timeouts**: Verify SSH key access to nodes
- **Package installation failures**: Check internet connectivity from nodes
- **Service mesh not starting**: Review logs with `kubectl logs -n <mesh-namespace>`

## References

- [Terraform OCI Provider Documentation](https://registry.terraform.io/providers/oracle/oci/latest/docs)
- [Ansible Documentation](https://docs.ansible.com/)
- [Oracle Cloud Free Tier](https://www.oracle.com/cloud/free/)
