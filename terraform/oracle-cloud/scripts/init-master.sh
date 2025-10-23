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

# Install Helm securely with direct binary download and checksum verification
HELM_VERSION="v3.14.0"
HELM_ARCH="linux-amd64"
HELM_TARBALL="helm-${HELM_VERSION}-${HELM_ARCH}.tar.gz"
HELM_URL="https://get.helm.sh/${HELM_TARBALL}"
# Official SHA256 checksum from https://github.com/helm/helm/releases/tag/v3.14.0
HELM_CHECKSUM="f43e1c3387de24547506ab05d24e5309c0ce0b228c23bd8aa64e9ec4b8206651"

echo "Installing Helm ${HELM_VERSION}..."

# Download Helm binary tarball
curl -fsSL "${HELM_URL}" -o "/tmp/${HELM_TARBALL}"

# Verify checksum of the actual Helm binary
echo "${HELM_CHECKSUM}  /tmp/${HELM_TARBALL}" | sha256sum -c - || {
    echo "ERROR: Helm binary checksum verification failed!" >&2
    echo "Expected: ${HELM_CHECKSUM}" >&2
    echo "Got: $(sha256sum /tmp/${HELM_TARBALL} | awk '{print $1}')" >&2
    rm -f "/tmp/${HELM_TARBALL}"
    exit 1
}

# Extract and install
tar -xzf "/tmp/${HELM_TARBALL}" -C /tmp/
sudo mv "/tmp/${HELM_ARCH}/helm" /usr/local/bin/helm
sudo chmod +x /usr/local/bin/helm

# Verify installation
helm version --short

# Cleanup
rm -rf "/tmp/${HELM_TARBALL}" "/tmp/${HELM_ARCH}"

echo "Helm ${HELM_VERSION} installed successfully with verified checksum"

# Install metrics-server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# SECURITY: Use hostNetwork instead of disabling TLS verification
# This is more secure than --kubelet-insecure-tls for test environments
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
  {"op": "add", "path": "/spec/template/spec/hostNetwork", "value": true},
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname"}
]'

# Note: For production, configure proper certificates:
# 1. Generate CA and certificates for kubelet
# 2. Configure kubelet with --client-ca-file
# 3. Remove hostNetwork and use proper TLS

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
