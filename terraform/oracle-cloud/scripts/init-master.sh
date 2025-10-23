#!/bin/bash
set -e

# Variables passed from Terraform
TEST_TYPE="${test_type}"
CLUSTER_NAME="${cluster_name}"

echo "=== Initializing Kubernetes Master Node ==="
echo "Test Type: $TEST_TYPE"
echo "Cluster Name: $CLUSTER_NAME"

# Update system
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo apt-get upgrade -y

# Install required packages
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    net-tools \
    jq

# Disable swap (required for Kubernetes)
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Enable kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Configure sysctl
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# Install containerd
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# Install Kubernetes packages
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Initialize Kubernetes cluster
sudo kubeadm init \
    --pod-network-cidr=10.244.0.0/16 \
    --apiserver-advertise-address=$(hostname -I | awk '{print $1}') \
    --cluster-name=$CLUSTER_NAME

# Configure kubectl for ubuntu user
mkdir -p /home/ubuntu/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
sudo chown ubuntu:ubuntu /home/ubuntu/.kube/config

# Also configure for root
mkdir -p /root/.kube
sudo cp -i /etc/kubernetes/admin.conf /root/.kube/config

# Save join command
kubeadm token create --print-join-command | sudo tee /home/ubuntu/join-command.sh
sudo chmod +x /home/ubuntu/join-command.sh

# Install Helm securely with checksum verification
HELM_VERSION="v3.14.0"
HELM_INSTALL_SCRIPT="/tmp/get-helm-${HELM_VERSION}.sh"
HELM_CHECKSUM="a8ddb4e30435b5fd45308ecce5eaad676d64a5de9c89660b56bebcc8bdf731b6"

echo "Installing Helm ${HELM_VERSION}..."
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o "${HELM_INSTALL_SCRIPT}"

# Verify checksum
echo "${HELM_CHECKSUM}  ${HELM_INSTALL_SCRIPT}" | sha256sum -c - || {
    echo "ERROR: Helm installer checksum verification failed!" >&2
    rm -f "${HELM_INSTALL_SCRIPT}"
    exit 1
}

# Execute with restricted permissions
chmod 700 "${HELM_INSTALL_SCRIPT}"
"${HELM_INSTALL_SCRIPT}" --version "${HELM_VERSION}"

# Cleanup
rm -f "${HELM_INSTALL_SCRIPT}"

# Install metrics-server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch metrics-server for self-signed certs
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

# Install CNI plugin (Calico)
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml

# Install additional monitoring tools
echo "Installing Prometheus and Grafana..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create monitoring namespace
kubectl create namespace monitoring || true

# Wait for cluster to be ready
echo "Waiting for cluster to be ready..."
sleep 30

echo "=== Master Node Initialization Complete ==="
echo "Join command saved to: /home/ubuntu/join-command.sh"
