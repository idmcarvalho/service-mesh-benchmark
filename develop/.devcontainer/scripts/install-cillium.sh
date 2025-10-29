#!/bin/bash
set -e
echo "Installing Cilium..."
CILIUM_CLI_VERSION="v0.15.17"
curl -L --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-amd64.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-amd64.tar.gz /usr/local/bin
rm cilium-linux-amd64.tar.gz{,.sha256sum}
cilium install --version 1.14.4
cilium hubble enable --ui
echo "Cilium installation complete!"
