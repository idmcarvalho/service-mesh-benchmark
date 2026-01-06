# Configuration Directory

This directory contains all configuration files for the Service Mesh Benchmark project, organized by environment and purpose.

## Directory Structure

### [local/](local/)
Local development configuration:
- `docker-compose.yml` - Docker Compose for local development stack
- `.pre-commit-config.yaml` - Git hooks configuration
- `.yamllint.yaml` - YAML linting rules

### [kubernetes/](kubernetes/)
Kubernetes-specific configuration files (planned)

### [monitoring/](monitoring/)
Monitoring and observability configuration:
- `prometheus.yml` - Prometheus scrape configuration
- `alerts.yml` - Prometheus alerting rules

### [templates/](templates/)
Configuration templates for various environments:
- `.env.example` - Environment variables template
- `backend.tf.example` - Terraform backend configuration template
- `terraform.tfvars.example` - Terraform variables template
- `ansible-inventory.ini.example` - Ansible inventory template

## Usage

### Local Development
1. Copy templates from `templates/` directory:
   ```bash
   cp config/templates/.env.example .env
   ```

2. Edit the copied files with your values

3. Use docker-compose from config directory:
   ```bash
   docker-compose -f config/local/docker-compose.yml up
   ```

### Production Deployment
1. Copy and customize templates:
   ```bash
   cp config/templates/terraform.tfvars.example terraform/oracle-cloud/terraform.tfvars
   cp config/templates/.env.example .env
   ```

2. Update values for your environment

3. Apply configurations using appropriate tools (Terraform, kubectl, etc.)

## Best Practices

- **Never commit sensitive data** - Always use `.example` or `.template` suffixes for files with secrets
- **Environment-specific configs** - Keep dev, staging, and production configs separate
- **Version control templates** - Commit template files to help others set up their environments
- **Document required variables** - Add comments to template files explaining each setting
