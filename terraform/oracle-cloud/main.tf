# Infraestrutura completa para benchmark em Oracle Cloud Free Tier
terraform {
  required_version = ">= 1.5.0"
  backend "local" {
    path = "terraform.tfstate"
  }
}

# Configuração do Provider OCI
provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

# Data Sources
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}

data "oci_core_images" "ubuntu" {
  compartment_id             = var.compartment_ocid
  operating_system           = "Canonical Ubuntu"
  operating_system_version   = "22.04"
  shape                      = var.instance_shape
  sort_by                    = "TIMECREATED"
  sort_order                 = "DESC"
}

# VCN (Virtual Cloud Network)
resource "oci_core_vcn" "benchmark_vcn" {
  compartment_id = var.compartment_ocid
  display_name   = "service-mesh-benchmark-vcn"
  cidr_blocks    = ["10.0.0.0/16"]
  dns_label      = "benchmark"
  
  freeform_tags = {
    "Project"     = "ServiceMeshBenchmark"
    "Environment" = "Research"
  }
}

# Internet Gateway
resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.benchmark_vcn.id
  display_name   = "benchmark-igw"
  enabled        = true
}

# Route Table
resource "oci_core_route_table" "public_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.benchmark_vcn.id
  display_name   = "public-route-table"
  
  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.igw.id
    description       = "Route to Internet"
  }
}

# Security List
resource "oci_core_security_list" "benchmark_sl" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.benchmark_vcn.id
  display_name   = "benchmark-security-list"
  
  # Egress - Allow all
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }
  
  # Ingress - SSH (Restrict to your IP - set via variable)
  ingress_security_rules {
    protocol = "6" # TCP
    source   = var.allowed_ssh_cidr

    tcp_options {
      min = 22
      max = 22
    }
  }

  # Ingress - Kubernetes API (Restrict to your IP - set via variable)
  ingress_security_rules {
    protocol = "6"
    source   = var.allowed_api_cidr

    tcp_options {
      min = 6443
      max = 6443
    }
  }

  # Ingress - NodePort Services (For load testing - can be restricted)
  ingress_security_rules {
    protocol = "6"
    source   = var.allowed_nodeport_cidr

    tcp_options {
      min = 30000
      max = 32767
    }
  }

  # Ingress - Hubble UI (Restrict to your IP)
  ingress_security_rules {
    protocol = "6"
    source   = var.allowed_ssh_cidr

    tcp_options {
      min = 8080
      max = 8090
    }
  }
  
  # Ingress - ICMP
  ingress_security_rules {
    protocol = "1" # ICMP
    source   = "0.0.0.0/0"
  }
  
  # Ingress - Internal cluster communication
  ingress_security_rules {
    protocol = "all"
    source   = "10.0.0.0/16"
  }
}

# Subnet
resource "oci_core_subnet" "public_subnet" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.benchmark_vcn.id
  cidr_block                 = "10.0.1.0/24"
  display_name               = "public-subnet"
  dns_label                  = "public"
  route_table_id             = oci_core_route_table.public_rt.id
  security_list_ids          = [oci_core_security_list.benchmark_sl.id]
  prohibit_public_ip_on_vnic = false
}

# Cluster Master Node
resource "oci_core_instance" "k8s_master" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "k8s-master-${var.test_type}"
  shape               = var.instance_shape
  
  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gb
  }
  
  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu.images[0].id
  }
  
  create_vnic_details {
    subnet_id        = oci_core_subnet.public_subnet.id
    display_name     = "k8s-master-vnic"
    assign_public_ip = true
    hostname_label   = "master"
  }
  
  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key_path)
    user_data = base64encode(templatefile("${path.module}/scripts/init-master.sh", {
      test_type    = var.test_type
      cluster_name = "benchmark-cluster"
    }))
  }
  
  freeform_tags = {
    "Name"     = "k8s-master"
    "Type"     = "master"
    "TestType" = var.test_type
  }
}

# Worker Nodes
resource "oci_core_instance" "k8s_workers" {
  count = var.worker_count
  
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "k8s-worker-${count.index + 1}-${var.test_type}"
  shape               = var.instance_shape
  
  shape_config {
    ocpus         = var.worker_ocpus
    memory_in_gbs = var.worker_memory_gb
  }
  
  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu.images[0].id
  }
  
  create_vnic_details {
    subnet_id        = oci_core_subnet.public_subnet.id
    display_name     = "k8s-worker-${count.index + 1}-vnic"
    assign_public_ip = true
    hostname_label   = "worker-${count.index + 1}"
  }
  
  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key_path)
    user_data = base64encode(templatefile("${path.module}/scripts/init-worker.sh", {
      master_ip    = oci_core_instance.k8s_master.private_ip
      worker_index = count.index + 1
    }))
  }
  
  freeform_tags = {
    "Name"     = "k8s-worker-${count.index + 1}"
    "Type"     = "worker"
    "TestType" = var.test_type
  }
  
  depends_on = [oci_core_instance.k8s_master]
}

# Load Balancer (para testes externos)
resource "oci_load_balancer_load_balancer" "benchmark_lb" {
  compartment_id = var.compartment_ocid
  display_name   = "benchmark-lb"
  shape          = "flexible"
  
  shape_details {
    minimum_bandwidth_in_mbps = 10
    maximum_bandwidth_in_mbps = 10
  }
  
  subnet_ids = [oci_core_subnet.public_subnet.id]
  
  freeform_tags = {
    "Project" = "ServiceMeshBenchmark"
  }
}

# Outputs are now in outputs.tf
# Kubeconfig will be generated via provisioner scripts