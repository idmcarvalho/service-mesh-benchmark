# Oracle Cloud Infrastructure Variables

# Authentication
variable "tenancy_ocid" {
  description = "OCID of your tenancy"
  type        = string
}

variable "user_ocid" {
  description = "OCID of the user calling the API"
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint for the key pair being used"
  type        = string
}

variable "private_key_path" {
  description = "Path to your private key file"
  type        = string
}

variable "region" {
  description = "OCI region"
  type        = string
  default     = "us-ashburn-1"
}

variable "compartment_ocid" {
  description = "OCID of the compartment to create resources in"
  type        = string
}

# SSH Configuration
variable "ssh_public_key_path" {
  description = "Path to your SSH public key"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

# Security Configuration
# SECURITY: No defaults for CIDR blocks - must be explicitly set
variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH into instances (e.g., 203.0.113.0/24). Must specify your actual IP range for security."
  type        = string
  # NO DEFAULT - force user to specify

  validation {
    condition     = can(cidrhost(var.allowed_ssh_cidr, 0))
    error_message = "Must be a valid CIDR block (e.g., 203.0.113.0/24)."
  }

  validation {
    condition     = var.allowed_ssh_cidr != "0.0.0.0/0"
    error_message = "Cannot use 0.0.0.0/0 - specify your actual IP range for security. Use 'curl ifconfig.me' to find your IP."
  }

  validation {
    condition     = !can(regex("^0\\.0\\.0\\.0/", var.allowed_ssh_cidr))
    error_message = "Cannot use 0.0.0.0 as the base address - specify a specific IP or range."
  }
}

variable "allowed_api_cidr" {
  description = "CIDR block allowed to access Kubernetes API (e.g., 203.0.113.0/24). Must specify your actual IP range for security."
  type        = string
  # NO DEFAULT - force user to specify

  validation {
    condition     = can(cidrhost(var.allowed_api_cidr, 0))
    error_message = "Must be a valid CIDR block (e.g., 203.0.113.0/24)."
  }

  validation {
    condition     = var.allowed_api_cidr != "0.0.0.0/0"
    error_message = "Cannot use 0.0.0.0/0 - specify your actual IP range for security. Use 'curl ifconfig.me' to find your IP."
  }

  validation {
    condition     = !can(regex("^0\\.0\\.0\\.0/", var.allowed_api_cidr))
    error_message = "Cannot use 0.0.0.0 as the base address - specify a specific IP or range."
  }
}

variable "allowed_nodeport_cidr" {
  description = "CIDR block allowed to access NodePort services (e.g., 203.0.113.0/24). Must specify your actual IP range for security."
  type        = string
  # NO DEFAULT - force user to specify

  validation {
    condition     = can(cidrhost(var.allowed_nodeport_cidr, 0))
    error_message = "Must be a valid CIDR block (e.g., 203.0.113.0/24)."
  }

  validation {
    condition     = var.allowed_nodeport_cidr != "0.0.0.0/0"
    error_message = "Cannot use 0.0.0.0/0 - specify your actual IP range for security. Use 'curl ifconfig.me' to find your IP."
  }

  validation {
    condition     = !can(regex("^0\\.0\\.0\\.0/", var.allowed_nodeport_cidr))
    error_message = "Cannot use 0.0.0.0 as the base address - specify a specific IP or range."
  }
}

# Instance Configuration
variable "instance_shape" {
  description = "Shape of the instances (use VM.Standard.A1.Flex for free tier ARM)"
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "instance_ocpus" {
  description = "Number of OCPUs for master node"
  type        = number
  default     = 2
  validation {
    condition     = var.instance_ocpus >= 1 && var.instance_ocpus <= 4
    error_message = "Free tier allows 1-4 OCPUs total across all instances."
  }
}

variable "instance_memory_gb" {
  description = "Memory in GB for master node"
  type        = number
  default     = 12
  validation {
    condition     = var.instance_memory_gb >= 1 && var.instance_memory_gb <= 24
    error_message = "Free tier allows up to 24GB RAM total across all instances."
  }
}

# Worker Node Configuration
variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
  validation {
    condition     = var.worker_count >= 0 && var.worker_count <= 3
    error_message = "Recommended 0-3 worker nodes for free tier."
  }
}

variable "worker_ocpus" {
  description = "Number of OCPUs per worker node"
  type        = number
  default     = 1
}

variable "worker_memory_gb" {
  description = "Memory in GB per worker node"
  type        = number
  default     = 6
}

# Test Configuration
variable "test_type" {
  description = "Type of test being run (e.g., istio, cilium, baseline)"
  type        = string
  default     = "benchmark"
  validation {
    condition     = contains(["istio", "cilium", "linkerd", "baseline", "benchmark"], var.test_type)
    error_message = "Test type must be one of: istio, cilium, linkerd, baseline, benchmark."
  }
}

# Network Configuration
variable "vcn_cidr" {
  description = "CIDR block for VCN"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

# Tags
variable "project_tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "ServiceMeshBenchmark"
    Environment = "Research"
    ManagedBy   = "Terraform"
  }
}
