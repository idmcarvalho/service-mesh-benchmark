# Terraform Outputs

output "instance_public_ip" {
  description = "Public IP address of the compute instance"
  value       = oci_core_instance.benchmark_instance.public_ip
}

output "instance_id" {
  description = "OCID of the compute instance"
  value       = oci_core_instance.benchmark_instance.id
}

output "instance_state" {
  description = "State of the compute instance"
  value       = oci_core_instance.benchmark_instance.state
}

output "vcn_id" {
  description = "OCID of the Virtual Cloud Network"
  value       = oci_core_vcn.benchmark_vcn.id
}

output "subnet_id" {
  description = "OCID of the subnet"
  value       = oci_core_subnet.benchmark_subnet.id
}

output "ssh_connection" {
  description = "SSH connection command"
  value       = "ssh -i ${var.ssh_private_key_path} ubuntu@${oci_core_instance.benchmark_instance.public_ip}"
}

output "application_urls" {
  description = "Application URLs"
  value = {
    frontend   = "http://${oci_core_instance.benchmark_instance.public_ip}:3000"
    api        = "http://${oci_core_instance.benchmark_instance.public_ip}:8000"
    api_docs   = "http://${oci_core_instance.benchmark_instance.public_ip}:8000/docs"
    prometheus = "http://${oci_core_instance.benchmark_instance.public_ip}:9090"
    grafana    = "http://${oci_core_instance.benchmark_instance.public_ip}:3001"
  }
}

output "next_steps" {
  description = "Next steps after Terraform apply"
  value = <<-EOT

  ============================================================
  Infrastructure created successfully!
  ============================================================

  Instance Public IP: ${oci_core_instance.benchmark_instance.public_ip}

  Next steps:

  1. Wait for instance to finish initialization (~2-3 minutes)

  2. Test SSH connection:
     ssh -i ${var.ssh_private_key_path} ubuntu@${oci_core_instance.benchmark_instance.public_ip}

  3. Run Ansible playbook to configure server:
     cd ../ansible
     ansible-playbook -i inventory/hosts.yml playbooks/setup-server.yml

  4. Deploy the application:
     ansible-playbook -i inventory/hosts.yml playbooks/deploy-app.yml

  5. Access your application:
     Frontend:   http://${oci_core_instance.benchmark_instance.public_ip}:3000
     API:        http://${oci_core_instance.benchmark_instance.public_ip}:8000
     API Docs:   http://${oci_core_instance.benchmark_instance.public_ip}:8000/docs
     Prometheus: http://${oci_core_instance.benchmark_instance.public_ip}:9090
     Grafana:    http://${oci_core_instance.benchmark_instance.public_ip}:3001

  ============================================================
  EOT
}
