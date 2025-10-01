# Terraform Outputs

# Master Node Information
output "master_public_ip" {
  description = "Public IP address of the Kubernetes master node"
  value       = oci_core_instance.k8s_master.public_ip
}

output "master_private_ip" {
  description = "Private IP address of the Kubernetes master node"
  value       = oci_core_instance.k8s_master.private_ip
}

output "master_instance_id" {
  description = "OCID of the master instance"
  value       = oci_core_instance.k8s_master.id
}

# Worker Nodes Information
output "worker_public_ips" {
  description = "Public IP addresses of worker nodes"
  value       = oci_core_instance.k8s_workers[*].public_ip
}

output "worker_private_ips" {
  description = "Private IP addresses of worker nodes"
  value       = oci_core_instance.k8s_workers[*].private_ip
}

output "worker_instance_ids" {
  description = "OCIDs of worker instances"
  value       = oci_core_instance.k8s_workers[*].id
}

# Network Information
output "vcn_id" {
  description = "OCID of the VCN"
  value       = oci_core_vcn.benchmark_vcn.id
}

output "subnet_id" {
  description = "OCID of the public subnet"
  value       = oci_core_subnet.public_subnet.id
}

# Load Balancer
output "load_balancer_ip" {
  description = "IP address of the load balancer"
  value       = oci_load_balancer_load_balancer.benchmark_lb.ip_address_details
}

output "load_balancer_id" {
  description = "OCID of the load balancer"
  value       = oci_load_balancer_load_balancer.benchmark_lb.id
}

# SSH Connection String
output "ssh_to_master" {
  description = "SSH command to connect to master node"
  value       = "ssh ubuntu@${oci_core_instance.k8s_master.public_ip}"
}

output "ssh_to_workers" {
  description = "SSH commands to connect to worker nodes"
  value = [
    for idx, worker in oci_core_instance.k8s_workers :
    "ssh ubuntu@${worker.public_ip}"
  ]
}

# Cluster Information
output "cluster_info" {
  description = "Summary of cluster configuration"
  value = {
    test_type     = var.test_type
    master_ip     = oci_core_instance.k8s_master.public_ip
    worker_count  = var.worker_count
    instance_type = var.instance_shape
    region        = var.region
  }
}
