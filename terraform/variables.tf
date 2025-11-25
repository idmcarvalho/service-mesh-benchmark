# Oracle Cloud Infrastructure Variables
# Configure these variables in terraform.tfvars

variable "tenancy_ocid" {
  description = "OCID of your tenancy"
  type        = string
}

variable "user_ocid" {
  description = "OCID of the user"
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint of the API key"
  type        = string
}

variable "private_key_path" {
  description = "Path to your OCI API private key"
  type        = string
}

variable "region" {
  description = "OCI region"
  type        = string
  default     = "us-ashburn-1"
}

variable "compartment_ocid" {
  description = "OCID of the compartment"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for instance access"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for provisioning"
  type        = string
}

# Instance Configuration
variable "instance_shape" {
  description = "Shape of the compute instance (Free tier: VM.Standard.E2.1.Micro)"
  type        = string
  default     = "VM.Standard.E2.1.Micro"
}

variable "instance_ocpus" {
  description = "Number of OCPUs (Free tier: 1)"
  type        = number
  default     = 1
}

variable "instance_memory_in_gbs" {
  description = "Amount of memory in GB (Free tier: 1)"
  type        = number
  default     = 1
}

variable "boot_volume_size_in_gbs" {
  description = "Size of boot volume in GB (Free tier: up to 50GB)"
  type        = number
  default     = 50
}

# Network Configuration
variable "vcn_cidr_block" {
  description = "CIDR block for VCN"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr_block" {
  description = "CIDR block for subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed for SSH access (use 0.0.0.0/0 for any, or your IP for security)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "allowed_http_cidr" {
  description = "CIDR block allowed for HTTP/HTTPS access"
  type        = string
  default     = "0.0.0.0/0"
}

# Application Configuration
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "service-mesh-benchmark"
}

# Domain Configuration (Optional)
variable "domain_name" {
  description = "Domain name for the application (optional)"
  type        = string
  default     = ""
}

# Tags
variable "freeform_tags" {
  description = "Free-form tags for all resources"
  type        = map(string)
  default = {
    Project     = "ServiceMeshBenchmark"
    ManagedBy   = "Terraform"
    Environment = "Production"
  }
}
