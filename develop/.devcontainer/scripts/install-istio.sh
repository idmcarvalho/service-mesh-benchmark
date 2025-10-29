#!/bin/bash
set -e
echo "Installing Istio..."
ISTIO_VERSION="1.20.0"
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION sh -
export PATH="$PWD/istio-$ISTIO_VERSION/bin:$PATH"
istioctl install --set profile=demo -y
kubectl label namespace default istio-injection=enabled --overwrite
echo "Istio installation complete!"
