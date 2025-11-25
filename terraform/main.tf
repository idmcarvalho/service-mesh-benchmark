# Service Mesh Benchmark - Oracle Cloud Infrastructure
# Terraform configuration for deploying to OCI Free Tier

terraform {
  required_version = ">= 1.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
  }

  # Optional: Configure remote backend for state management
  # backend "s3" {
  #   bucket = "terraform-state-bucket"
  #   key    = "service-mesh-benchmark/terraform.tfstate"
  #   region = "us-ashburn-1"
  # }
}

# Configure the Oracle Cloud Infrastructure provider
provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

# Data source for availability domains
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# Data source for Ubuntu 22.04 image
data "oci_core_images" "ubuntu_22_04" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# Virtual Cloud Network (VCN)
resource "oci_core_vcn" "benchmark_vcn" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr_block]
  display_name   = "${var.project_name}-vcn"
  dns_label      = "benchmarkvcn"
  freeform_tags  = var.freeform_tags
}

# Internet Gateway
resource "oci_core_internet_gateway" "benchmark_ig" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.benchmark_vcn.id
  display_name   = "${var.project_name}-ig"
  enabled        = true
  freeform_tags  = var.freeform_tags
}

# Route Table
resource "oci_core_route_table" "benchmark_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.benchmark_vcn.id
  display_name   = "${var.project_name}-rt"
  freeform_tags  = var.freeform_tags

  route_rules {
    network_entity_id = oci_core_internet_gateway.benchmark_ig.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }
}

# Security List
resource "oci_core_security_list" "benchmark_sl" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.benchmark_vcn.id
  display_name   = "${var.project_name}-sl"
  freeform_tags  = var.freeform_tags

  # Egress: Allow all outbound traffic
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
    stateless   = false
  }

  # Ingress: SSH (22)
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = var.allowed_ssh_cidr
    stateless   = false
    description = "SSH access"

    tcp_options {
      min = 22
      max = 22
    }
  }

  # Ingress: HTTP (80)
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = var.allowed_http_cidr
    stateless   = false
    description = "HTTP access"

    tcp_options {
      min = 80
      max = 80
    }
  }

  # Ingress: HTTPS (443)
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = var.allowed_http_cidr
    stateless   = false
    description = "HTTPS access"

    tcp_options {
      min = 443
      max = 443
    }
  }

  # Ingress: Frontend (3000)
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = var.allowed_http_cidr
    stateless   = false
    description = "Frontend application"

    tcp_options {
      min = 3000
      max = 3000
    }
  }

  # Ingress: API (8000)
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = var.allowed_http_cidr
    stateless   = false
    description = "API application"

    tcp_options {
      min = 8000
      max = 8000
    }
  }

  # Ingress: Prometheus (9090)
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = var.allowed_http_cidr
    stateless   = false
    description = "Prometheus monitoring"

    tcp_options {
      min = 9090
      max = 9090
    }
  }

  # Ingress: Grafana (3001)
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = var.allowed_http_cidr
    stateless   = false
    description = "Grafana dashboards"

    tcp_options {
      min = 3001
      max = 3001
    }
  }

  # Ingress: ICMP for ping
  ingress_security_rules {
    protocol    = "1" # ICMP
    source      = "0.0.0.0/0"
    stateless   = false
    description = "ICMP for ping"

    icmp_options {
      type = 3
      code = 4
    }
  }

  ingress_security_rules {
    protocol    = "1" # ICMP
    source      = var.vcn_cidr_block
    stateless   = false
    description = "ICMP within VCN"

    icmp_options {
      type = 3
    }
  }
}

# Public Subnet
resource "oci_core_subnet" "benchmark_subnet" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.benchmark_vcn.id
  cidr_block                 = var.subnet_cidr_block
  display_name               = "${var.project_name}-subnet"
  dns_label                  = "benchmarksub"
  route_table_id             = oci_core_route_table.benchmark_rt.id
  security_list_ids          = [oci_core_security_list.benchmark_sl.id]
  prohibit_public_ip_on_vnic = false
  freeform_tags              = var.freeform_tags
}

# Compute Instance (Free Tier)
resource "oci_core_instance" "benchmark_instance" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "${var.project_name}-instance"
  shape               = var.instance_shape
  freeform_tags       = var.freeform_tags

  # Free tier shape config
  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_in_gbs
  }

  # Boot volume
  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_22_04.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
  }

  # Network configuration
  create_vnic_details {
    subnet_id        = oci_core_subnet.benchmark_subnet.id
    display_name     = "${var.project_name}-vnic"
    assign_public_ip = true
    hostname_label   = var.project_name
  }

  # SSH key
  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
      hostname = var.project_name
    }))
  }

  # Preserve boot volume on instance termination
  preserve_boot_volume = false

  # Lifecycle
  lifecycle {
    ignore_changes = [
      source_details[0].source_id, # Ignore image updates
    ]
  }
}

# Generate Ansible inventory file
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    instance_ip         = oci_core_instance.benchmark_instance.public_ip
    ssh_private_key     = var.ssh_private_key_path
    instance_user       = "ubuntu"
    environment         = var.environment
    domain_name         = var.domain_name
  })
  filename = "${path.module}/../ansible/inventory/hosts.yml"

  depends_on = [oci_core_instance.benchmark_instance]
}

# Output instance details to be used by Ansible
resource "local_file" "terraform_outputs" {
  content = jsonencode({
    instance_ip   = oci_core_instance.benchmark_instance.public_ip
    instance_id   = oci_core_instance.benchmark_instance.id
    vcn_id        = oci_core_vcn.benchmark_vcn.id
    subnet_id     = oci_core_subnet.benchmark_subnet.id
    environment   = var.environment
    domain_name   = var.domain_name
  })
  filename = "${path.module}/terraform_outputs.json"

  depends_on = [oci_core_instance.benchmark_instance]
}
