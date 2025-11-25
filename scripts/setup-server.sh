#!/bin/bash

# Service Mesh Benchmark - Server Setup Script for Oracle Cloud
# This script sets up a fresh Ubuntu 22.04 instance with all required dependencies

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Service Mesh Benchmark - Server Setup                    ║${NC}"
echo -e "${BLUE}║  Oracle Cloud Ubuntu 22.04                                 ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo ""

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Error: This script must be run as root or with sudo${NC}"
    echo -e "${YELLOW}Please run: sudo bash setup-server.sh${NC}"
    exit 1
fi

echo -e "${BLUE}📋 System Information:${NC}"
echo -e "  OS: $(lsb_release -d | cut -f2)"
echo -e "  Kernel: $(uname -r)"
echo -e "  Architecture: $(uname -m)"
echo ""

# Update system packages
echo -e "${BLUE}📦 Updating system packages...${NC}"
apt-get update -qq
apt-get upgrade -y -qq
echo -e "${GREEN}✓ System packages updated${NC}"
echo ""

# Install required packages
echo -e "${BLUE}📦 Installing required packages...${NC}"
apt-get install -y -qq \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    git \
    vim \
    htop \
    net-tools \
    jq \
    unzip

echo -e "${GREEN}✓ Required packages installed${NC}"
echo ""

# Install Docker
if command -v docker &> /dev/null; then
    echo -e "${YELLOW}⚠️  Docker is already installed${NC}"
    docker --version
else
    echo -e "${BLUE}🐋 Installing Docker...${NC}"

    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Set up Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker Engine
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Start and enable Docker
    systemctl start docker
    systemctl enable docker

    echo -e "${GREEN}✓ Docker installed successfully${NC}"
    docker --version
fi
echo ""

# Add current user to docker group (if not root)
if [ -n "$SUDO_USER" ]; then
    echo -e "${BLUE}👤 Adding $SUDO_USER to docker group...${NC}"
    usermod -aG docker "$SUDO_USER"
    echo -e "${GREEN}✓ User added to docker group${NC}"
    echo -e "${YELLOW}⚠️  Please log out and log back in for group changes to take effect${NC}"
else
    echo -e "${YELLOW}⚠️  Running as root, skipping docker group setup${NC}"
fi
echo ""

# Configure firewall (Oracle Cloud uses iptables)
echo -e "${BLUE}🔥 Configuring firewall rules...${NC}"

# Check if firewall is active
if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
    echo -e "${BLUE}   Configuring UFW...${NC}"
    ufw allow 22/tcp comment 'SSH'
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    ufw allow 3000/tcp comment 'Frontend'
    ufw allow 8000/tcp comment 'API'
    ufw allow 9090/tcp comment 'Prometheus'
    ufw allow 3001/tcp comment 'Grafana'
    echo -e "${GREEN}   ✓ UFW rules configured${NC}"
else
    echo -e "${YELLOW}   ℹ️  UFW not active, configuring iptables directly...${NC}"

    # Allow established connections
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT

    # Allow SSH
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT

    # Allow HTTP/HTTPS
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT

    # Allow application ports
    iptables -A INPUT -p tcp --dport 3000 -j ACCEPT  # Frontend
    iptables -A INPUT -p tcp --dport 8000 -j ACCEPT  # API
    iptables -A INPUT -p tcp --dport 9090 -j ACCEPT  # Prometheus
    iptables -A INPUT -p tcp --dport 3001 -j ACCEPT  # Grafana

    # Save iptables rules
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save
    elif command -v iptables-save &> /dev/null; then
        iptables-save > /etc/iptables/rules.v4
    fi

    echo -e "${GREEN}   ✓ iptables rules configured${NC}"
fi

echo -e "${YELLOW}⚠️  Don't forget to configure Oracle Cloud Security List/NSG to allow these ports:${NC}"
echo -e "   - TCP 22 (SSH)"
echo -e "   - TCP 80 (HTTP)"
echo -e "   - TCP 443 (HTTPS)"
echo -e "   - TCP 3000 (Frontend)"
echo -e "   - TCP 8000 (API)"
echo -e "   - TCP 9090 (Prometheus)"
echo -e "   - TCP 3001 (Grafana)"
echo ""

# Install kubectl (for Kubernetes interaction)
echo -e "${BLUE}☸️  Installing kubectl...${NC}"
if command -v kubectl &> /dev/null; then
    echo -e "${YELLOW}⚠️  kubectl is already installed${NC}"
    kubectl version --client
else
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
    apt-get update -qq
    apt-get install -y -qq kubectl
    echo -e "${GREEN}✓ kubectl installed successfully${NC}"
    kubectl version --client
fi
echo ""

# Optimize system for Docker and networking
echo -e "${BLUE}⚙️  Optimizing system settings...${NC}"

# Increase file descriptors
cat >> /etc/security/limits.conf <<EOF
# Service Mesh Benchmark optimizations
* soft nofile 65536
* hard nofile 65536
* soft nproc 4096
* hard nproc 4096
EOF

# Kernel parameters for networking
cat >> /etc/sysctl.conf <<EOF

# Service Mesh Benchmark networking optimizations
net.core.somaxconn = 1024
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.core.netdev_max_backlog = 2048

# eBPF optimizations
kernel.unprivileged_bpf_disabled = 0

# eBPF JIT compilation (critical for performance)
net.core.bpf_jit_enable = 1
net.core.bpf_jit_harden = 0
net.core.bpf_jit_kallsyms = 1
EOF

sysctl -p > /dev/null 2>&1

echo -e "${GREEN}✓ System optimizations applied${NC}"
echo ""

# Create application directory
echo -e "${BLUE}📁 Creating application directory...${NC}"
APP_DIR="/opt/service-mesh-benchmark"
mkdir -p "$APP_DIR"

# Set ownership to the sudo user if available
if [ -n "$SUDO_USER" ]; then
    chown -R "$SUDO_USER:$SUDO_USER" "$APP_DIR"
    echo -e "${GREEN}✓ Application directory created at $APP_DIR${NC}"
    echo -e "${GREEN}   Owned by: $SUDO_USER${NC}"
else
    echo -e "${GREEN}✓ Application directory created at $APP_DIR${NC}"
fi
echo ""

# Display completion message
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            Server Setup Complete! 🎉                       ║${NC}"
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo ""
if [ -n "$SUDO_USER" ]; then
    echo -e "1. Log out and log back in to apply docker group membership:"
    echo -e "   ${YELLOW}exit${NC}"
    echo -e ""
    echo -e "2. Clone the repository:"
    echo -e "   ${YELLOW}cd $APP_DIR${NC}"
    echo -e "   ${YELLOW}git clone <repository-url> .${NC}"
    echo -e ""
    echo -e "3. Configure environment:"
    echo -e "   ${YELLOW}cp .env.production.example .env.production${NC}"
    echo -e "   ${YELLOW}vim .env.production${NC}"
    echo -e ""
    echo -e "4. Deploy the application:"
    echo -e "   ${YELLOW}chmod +x scripts/deploy.sh${NC}"
    echo -e "   ${YELLOW}./scripts/deploy.sh${NC}"
else
    echo -e "1. Clone the repository:"
    echo -e "   ${YELLOW}cd $APP_DIR${NC}"
    echo -e "   ${YELLOW}git clone <repository-url> .${NC}"
    echo -e ""
    echo -e "2. Configure environment:"
    echo -e "   ${YELLOW}cp .env.production.example .env.production${NC}"
    echo -e "   ${YELLOW}vim .env.production${NC}"
    echo -e ""
    echo -e "3. Deploy the application:"
    echo -e "   ${YELLOW}chmod +x scripts/deploy.sh${NC}"
    echo -e "   ${YELLOW}./scripts/deploy.sh${NC}"
fi
echo ""
echo -e "${YELLOW}Remember to configure Oracle Cloud Security List/NSG!${NC}"
echo ""
