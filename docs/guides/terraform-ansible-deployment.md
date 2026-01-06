# Terraform & Ansible Deployment Guide

This guide provides complete instructions for deploying the Service Mesh Benchmark application to Oracle Cloud Infrastructure (OCI) using Terraform and Ansible.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [OCI Setup](#oci-setup)
4. [Terraform Configuration](#terraform-configuration)
5. [Infrastructure Deployment](#infrastructure-deployment)
6. [Ansible Configuration](#ansible-configuration)
7. [Application Deployment](#application-deployment)
8. [Verification](#verification)
9. [Management and Maintenance](#management-and-maintenance)
10. [Troubleshooting](#troubleshooting)
11. [Cleanup](#cleanup)

## Overview

### Architecture

This deployment uses:
- **Terraform**: Infrastructure as Code (IaC) for provisioning OCI resources
- **Ansible**: Configuration management and application deployment
- **Docker Compose**: Container orchestration

### What Gets Deployed

**Infrastructure (Terraform)**:
- OCI Compute Instance (VM.Standard.E2.1.Micro - Free Tier)
- Virtual Cloud Network (VCN)
- Internet Gateway
- Route Table
- Security List (Firewall Rules)
- Public Subnet
- Public IP Address

**Application Stack (Ansible + Docker Compose)**:
- PostgreSQL 16 (Database)
- Redis 7 (Job Queue)
- FastAPI (Backend API)
- SvelteKit (Frontend)
- Prometheus (Metrics)
- Grafana (Dashboards)

## Prerequisites

### Local Machine Requirements

1. **Terraform** (>= 1.0)
   ```bash
   # Download from: https://www.terraform.io/downloads
   # Or use package manager:

   # macOS
   brew install terraform

   # Linux
   wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
   unzip terraform_1.6.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   ```

2. **Ansible** (>= 2.14)
   ```bash
   # macOS
   brew install ansible

   # Linux
   sudo apt-get update
   sudo apt-get install ansible

   # Python pip
   pip3 install ansible
   ```

3. **Git**
   ```bash
   # macOS
   brew install git

   # Linux
   sudo apt-get install git
   ```

4. **SSH Client** (usually pre-installed)

### Oracle Cloud Account

1. **Free Tier Account**: Sign up at https://www.oracle.com/cloud/free/
2. **API Keys**: You'll need OCI API credentials

## OCI Setup

### 1. Create OCI API Keys

```bash
# Create .oci directory
mkdir -p ~/.oci

# Generate API key pair
openssl genrsa -out ~/.oci/oci_api_key.pem 2048
chmod 600 ~/.oci/oci_api_key.pem

# Generate public key
openssl rsa -pubout -in ~/.oci/oci_api_key.pem -out ~/.oci/oci_api_key_public.pem
```

### 2. Upload Public Key to OCI

1. Log in to OCI Console: https://cloud.oracle.com/
2. Click on your **Profile** icon (top right)
3. Select **User Settings**
4. Under **Resources**, click **API Keys**
5. Click **Add API Key**
6. Select **Paste Public Key**
7. Paste contents of `~/.oci/oci_api_key_public.pem`
8. Click **Add**

**Important**: Note the fingerprint displayed!

### 3. Get Required OCIDs

You'll need the following OCIDs:

**Tenancy OCID**:
1. Profile icon → **Tenancy: [name]**
2. Copy the OCID (starts with `ocid1.tenancy.oc1..`)

**User OCID**:
1. Profile icon → **User Settings**
2. Copy the OCID (starts with `ocid1.user.oc1..`)

**Compartment OCID**:
1. **Menu** → **Identity & Security** → **Compartments**
2. Use root compartment OCID or create a new one
3. Copy the OCID (starts with `ocid1.compartment.oc1..` or `ocid1.tenancy.oc1..` for root)

### 4. Create SSH Key Pair for Instance Access

```bash
# Create SSH key for instance access
ssh-keygen -t rsa -b 4096 -f ~/.ssh/oci_benchmark_key -C "benchmark@oci"
chmod 600 ~/.ssh/oci_benchmark_key
chmod 644 ~/.ssh/oci_benchmark_key.pub
```

## Terraform Configuration

### 1. Navigate to Terraform Directory

```bash
cd terraform
```

### 2. Create terraform.tfvars File

```bash
# Copy example file
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
vim terraform.tfvars  # or nano, code, etc.
```

### 3. Configure terraform.tfvars

**Minimum required configuration**:

```hcl
# OCI Authentication
tenancy_ocid     = "ocid1.tenancy.oc1..aaaaaaaa..."
user_ocid        = "ocid1.user.oc1..aaaaaaaa..."
fingerprint      = "aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99"
private_key_path = "~/.oci/oci_api_key.pem"

# Region and Compartment
region           = "us-ashburn-1"
compartment_ocid = "ocid1.compartment.oc1..aaaaaaaa..."

# SSH Configuration
ssh_public_key = <<-EOT
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC... benchmark@oci
EOT

ssh_private_key_path = "~/.ssh/oci_benchmark_key"

# Free Tier Configuration (already set as defaults)
instance_shape           = "VM.Standard.E2.1.Micro"
instance_ocpus           = 1
instance_memory_in_gbs   = 1
boot_volume_size_in_gbs  = 50
```

**Get your SSH public key content**:
```bash
cat ~/.ssh/oci_benchmark_key.pub
```

**Optional: Restrict SSH Access** (Recommended for production):
```hcl
# Find your IP address
# Run: curl ifconfig.me

allowed_ssh_cidr = "YOUR.IP.ADDRESS/32"  # Replace with your IP
```

## Infrastructure Deployment

### 1. Initialize Terraform

```bash
terraform init
```

This downloads the OCI provider and initializes the backend.

### 2. Validate Configuration

```bash
terraform validate
```

Should return: "Success! The configuration is valid."

### 3. Plan Infrastructure

```bash
terraform plan
```

Review the resources that will be created:
- 1 VCN
- 1 Internet Gateway
- 1 Route Table
- 1 Security List
- 1 Subnet
- 1 Compute Instance
- 2 Local Files (inventory, outputs)

### 4. Apply Configuration

```bash
terraform apply
```

Type `yes` when prompted.

**Expected duration**: 2-3 minutes

### 5. Save Outputs

```bash
# Display outputs
terraform output

# Save to file
terraform output -json > ../outputs.json
```

**Important**: Note the public IP address displayed!

### 6. Verify Instance

Wait 2-3 minutes for cloud-init to complete, then test SSH:

```bash
# Get SSH command from output
terraform output ssh_connection

# Or manually
ssh -i ~/.ssh/oci_benchmark_key ubuntu@<PUBLIC_IP>
```

## Ansible Configuration

### 1. Verify Inventory

Terraform automatically generated the Ansible inventory file:

```bash
cat ../ansible/inventory/hosts.yml
```

You should see your instance IP and configuration.

### 2. Test Ansible Connectivity

```bash
cd ../ansible

# Ping test
ansible all -m ping

# Should return:
# benchmark_instance | SUCCESS => {
#     "changed": false,
#     "ping": "pong"
# }
```

### 3. Verify Ansible Configuration

```bash
# Check inventory
ansible-inventory --list

# Check host variables
ansible-inventory --host benchmark_instance
```

## Application Deployment

### Two-Step Deployment Process

#### Step 1: Server Setup

```bash
cd ansible

# Run server setup playbook
ansible-playbook -i inventory/hosts.yml playbooks/setup-server.yml
```

This playbook:
- Installs Docker and Docker Compose
- Installs kubectl
- Configures system optimizations
- Sets up application directory
- Configures firewall

**Duration**: 5-10 minutes

#### Step 2: Application Deployment

```bash
# Run application deployment playbook
ansible-playbook -i inventory/hosts.yml playbooks/deploy-app.yml
```

You'll be prompted for passwords (or press Enter to auto-generate):
- PostgreSQL password
- Redis password
- Secret key
- Grafana password

This playbook:
- Clones the application repository
- Generates environment configuration
- Builds Docker images
- Starts all services
- Performs health checks
- Saves credentials

**Duration**: 10-15 minutes (first run)

### Update Repository URL

**Before deploying**, update the repository URL in `playbooks/deploy-app.yml`:

```bash
vim playbooks/deploy-app.yml

# Change line 7:
repo_url: "https://github.com/YOUR-ORG/service-mesh-benchmark.git"
```

## Verification

### 1. Check Service Status

```bash
# SSH to instance
ssh -i ~/.ssh/oci_benchmark_key ubuntu@<PUBLIC_IP>

# Check containers
docker ps

# Should show 6 containers running:
# - benchmark-postgres
# - benchmark-redis
# - benchmark-api
# - benchmark-frontend
# - benchmark-prometheus
# - benchmark-grafana

# Check logs
docker-compose -f /opt/service-mesh-benchmark/docker-compose.prod.yml logs -f
```

### 2. Access Applications

From your browser:

- **Frontend**: `http://<PUBLIC_IP>:3000`
- **API**: `http://<PUBLIC_IP>:8000`
- **API Documentation**: `http://<PUBLIC_IP>:8000/docs`
- **Prometheus**: `http://<PUBLIC_IP>:9090`
- **Grafana**: `http://<PUBLIC_IP>:3001`

### 3. Grafana Login

Credentials are in `/opt/service-mesh-benchmark/CREDENTIALS.txt`:

```bash
ssh -i ~/.ssh/oci_benchmark_key ubuntu@<PUBLIC_IP>
cat /opt/service-mesh-benchmark/CREDENTIALS.txt
```

Default username: `admin`

### 4. Test API

```bash
# Health check
curl http://<PUBLIC_IP>:8000/health

# Should return: {"status":"healthy"}
```

## Management and Maintenance

### Update Application

```bash
cd ansible

# Pull latest changes and redeploy
ansible-playbook -i inventory/hosts.yml playbooks/deploy-app.yml --tags update
```

### Restart Services

```bash
# From local machine via Ansible
ansible benchmark_servers -a "docker-compose -f /opt/service-mesh-benchmark/docker-compose.prod.yml restart"

# Or SSH to instance
ssh -i ~/.ssh/oci_benchmark_key ubuntu@<PUBLIC_IP>
cd /opt/service-mesh-benchmark
docker-compose -f docker-compose.prod.yml restart
```

### View Logs

```bash
# Specific service
docker-compose -f docker-compose.prod.yml logs -f api

# All services
docker-compose -f docker-compose.prod.yml logs -f

# Last 100 lines
docker-compose -f docker-compose.prod.yml logs --tail=100
```

### Backup Database

```bash
# Create backup
docker exec benchmark-postgres pg_dump -U benchmark service_mesh_benchmark > backup_$(date +%Y%m%d).sql

# Download backup to local machine
scp -i ~/.ssh/oci_benchmark_key ubuntu@<PUBLIC_IP>:backup_*.sql ./
```

### Infrastructure Changes

```bash
cd terraform

# Make changes to *.tf files

# Preview changes
terraform plan

# Apply changes
terraform apply
```

## Troubleshooting

### Terraform Issues

**Issue**: "Error 401-NotAuthenticated"
```bash
# Verify credentials
cat ~/.oci/oci_api_key.pem  # Should exist
cat terraform.tfvars         # Check fingerprint matches

# Test OCI CLI (optional)
oci iam region list --config-file ~/.oci/config
```

**Issue**: "Service limit exceeded"
```bash
# Free tier limits:
# - 2 VMs (VM.Standard.E2.1.Micro)
# - 2 VCNs
# Check existing resources in OCI Console
```

**Issue**: "Subnet overlaps with existing VCN"
```bash
# Change VCN CIDR in terraform.tfvars
vcn_cidr_block = "10.1.0.0/16"  # Different from existing VCNs
```

### Ansible Issues

**Issue**: "Permission denied (publickey)"
```bash
# Check SSH key permissions
chmod 600 ~/.ssh/oci_benchmark_key

# Test SSH manually
ssh -i ~/.ssh/oci_benchmark_key ubuntu@<PUBLIC_IP>

# Verify inventory
cat ansible/inventory/hosts.yml
```

**Issue**: "Failed to connect to the host"
```bash
# Wait for cloud-init to complete
ssh -i ~/.ssh/oci_benchmark_key ubuntu@<PUBLIC_IP> 'tail -f /var/log/cloud-init-output.log'

# Check OCI Security List allows SSH (port 22)
```

**Issue**: "Docker not found"
```bash
# Re-run server setup
ansible-playbook -i inventory/hosts.yml playbooks/setup-server.yml

# Check Docker status
ansible benchmark_servers -a "systemctl status docker"
```

### Application Issues

**Issue**: "Containers won't start"
```bash
# Check logs
ssh -i ~/.ssh/oci_benchmark_key ubuntu@<PUBLIC_IP>
cd /opt/service-mesh-benchmark
docker-compose -f docker-compose.prod.yml logs

# Check disk space (free tier: 50GB)
df -h

# Check memory (free tier: 1GB)
free -h
```

**Issue**: "Cannot access frontend"
```bash
# Check OCI Security List allows port 3000
# Verify container is running
docker ps | grep frontend

# Check frontend logs
docker logs benchmark-frontend
```

**Issue**: "Database connection errors"
```bash
# Check PostgreSQL is running
docker logs benchmark-postgres

# Verify password in .env.production matches
cat /opt/service-mesh-benchmark/.env.production | grep POSTGRES_PASSWORD
```

## Cleanup

### Destroy Infrastructure

```bash
cd terraform

# Preview what will be deleted
terraform plan -destroy

# Destroy all resources
terraform destroy

# Type 'yes' when prompted
```

This will delete:
- Compute instance
- VCN and networking components
- All associated resources

**Note**: This does NOT delete:
- OCI API keys
- SSH keys on your local machine
- Downloaded Docker images on your machine

### Manual Cleanup

If `terraform destroy` fails:

1. **Go to OCI Console**
2. **Compute** → **Instances** → Terminate instance
3. **Networking** → **Virtual Cloud Networks** → Delete VCN
   - Delete Subnets first
   - Delete Route Tables
   - Delete Internet Gateways
   - Delete Security Lists
   - Then delete VCN

## Advanced Topics

### Using a Custom Domain

1. **Update terraform.tfvars**:
   ```hcl
   domain_name = "benchmark.example.com"
   ```

2. **Point DNS A record** to the public IP

3. **Re-run Ansible**:
   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/deploy-app.yml
   ```

### Adding SSL/TLS

Create a new playbook `playbooks/setup-ssl.yml`:

```yaml
---
- name: Setup SSL/TLS with Let's Encrypt
  hosts: benchmark_servers
  become: true
  tasks:
    - name: Install Certbot
      apt:
        name:
          - certbot
          - python3-certbot-nginx
        state: present

    - name: Obtain SSL certificate
      command: >
        certbot certonly --standalone
        -d {{ domain_name }}
        --non-interactive
        --agree-tos
        -m admin@{{ domain_name }}
      when: domain_name is defined and domain_name != ""
```

### Scaling for Production

For production workloads, consider:

1. **Larger instance**: VM.Standard.E4.Flex (paid)
2. **Block storage**: Additional volumes for data
3. **Load balancer**: OCI Load Balancer
4. **Database**: OCI MySQL or Autonomous Database
5. **Backups**: OCI Object Storage for backups

## Additional Resources

- [Terraform OCI Provider Docs](https://registry.terraform.io/providers/oracle/oci/latest/docs)
- [Ansible Documentation](https://docs.ansible.com/)
- [OCI Documentation](https://docs.oracle.com/en-us/iaas/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)

## Support

For issues:
1. Check [Troubleshooting](#troubleshooting) section
2. Review logs: Terraform, Ansible, Docker
3. Check OCI service limits and quotas
4. Open an issue on the project repository

---

**Last Updated**: 2025-11-01
