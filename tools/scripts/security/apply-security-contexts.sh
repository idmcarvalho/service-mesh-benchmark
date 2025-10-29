#!/bin/bash
# shellcheck shell=bash
set -euo pipefail

# Script to document security context additions
# This is a reference for the manual changes applied to Kubernetes manifests

echo "Security Context Application Summary"
echo "===================================="
echo ""
echo "The following Kubernetes workloads have been updated with security contexts:"
echo ""
echo "✅ http-service.yaml"
echo "  - http-server deployment: nginx user (UID 101)"
echo "  - http-client deployment: curl user (UID 100)"
echo "  - Added emptyDir volumes for /tmp, /var/cache/nginx, /var/run, /var/log/nginx"
echo ""
echo "Remaining workloads to update:"
echo "- grpc-service.yaml"
echo "- websocket-service.yaml"
echo "- database-cluster.yaml"
echo "- baseline-http-service.yaml"
echo "- baseline-grpc-service.yaml"
echo ""
echo "Standard Security Context Template:"
echo "-----------------------------------"
cat << 'EOF'

# Pod-level security context
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault

# Container-level security context
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 1000
  capabilities:
    drop:
      - ALL
    # add: ["NET_BIND_SERVICE"]  # Only if needed for port < 1024

# Required volumes for read-only root filesystem
volumes:
- name: tmp
  emptyDir: {}
- name: cache
  emptyDir: {}

volumeMounts:
- name: tmp
  mountPath: /tmp
- name: cache
  mountPath: /path/to/cache

EOF

echo ""
echo "Notes:"
echo "- Adjust runAsUser based on the container image (e.g., nginx=101, postgres=999)"
echo "- Add NET_BIND_SERVICE capability only for ports < 1024"
echo "- Add emptyDir volumes for any writable directories needed"
echo ""
