# MCP Integration for DevOps

This guide explains how to use Model Context Protocol (MCP) servers with Claude Code for DevOps automation in the Service Mesh Benchmark project.

## Overview

The project integrates with five CNCF-ecosystem MCP servers to enable AI-powered DevOps workflows:

| MCP Server | CNCF Status | Purpose |
|------------|-------------|---------|
| Kubernetes | - | Cluster management, pod operations, resource CRUD |
| Prometheus | Graduated | Metrics querying, performance analysis |
| ArgoCD | Graduated | GitOps continuous delivery |
| Helm | - | Package management for Kubernetes |
| LitmusChaos | Incubating | Chaos engineering and resilience testing |

## Prerequisites

### Required Tools

```bash
# Node.js (for npx-based servers)
node --version  # v18+ recommended

# Docker (for containerized servers)
docker --version

# Python with uv (for Helm server)
pip install uv
```

### Environment Variables

Create a `.env` file or export these variables:

```bash
# Kubernetes
export KUBECONFIG=~/.kube/config

# Prometheus
export PROMETHEUS_URL=http://localhost:9090
export PROMETHEUS_USERNAME=""  # Optional
export PROMETHEUS_PASSWORD=""  # Optional

# ArgoCD
export ARGOCD_SERVER=localhost:8080
export ARGOCD_AUTH_TOKEN="your-argocd-token"
export ARGOCD_INSECURE=true  # Set to false for production

# LitmusChaos
export CHAOS_CENTER_ENDPOINT=http://localhost:8080
export LITMUS_PROJECT_ID="your-project-id"
export LITMUS_ACCESS_TOKEN="your-access-token"
```

## MCP Server Capabilities

### Kubernetes MCP Server

**Source**: [containers/kubernetes-mcp-server](https://github.com/containers/kubernetes-mcp-server)

Tools available:
- `list_pods` - List pods in a namespace
- `get_pod` - Get detailed pod information
- `delete_pod` - Delete a pod
- `pod_logs` - Retrieve pod logs
- `pod_exec` - Execute commands in pods
- `list_namespaces` - List all namespaces
- `get_events` - Get Kubernetes events
- `apply_resource` - Apply YAML manifests
- `helm_install` - Install Helm charts
- `helm_list` - List Helm releases
- `helm_uninstall` - Uninstall Helm releases

Example queries:
```
"List all pods in the istio-system namespace"
"Show me the logs from the benchmark-runner pod"
"What events occurred in the last hour?"
```

### Prometheus MCP Server

**Source**: [pab1it0/prometheus-mcp-server](https://github.com/pab1it0/prometheus-mcp-server)

Tools available:
- `health_check` - Check Prometheus status
- `execute_query` - Run instant PromQL queries
- `execute_range_query` - Run range queries with intervals
- `list_metrics` - List available metrics
- `get_metric_metadata` - Get metric metadata
- `get_targets` - List scrape targets

Example queries:
```
"What's the current request latency p99 for the frontend service?"
"Show me CPU usage over the last hour"
"List all metrics related to istio"
```

### ArgoCD MCP Server

**Source**: [argoproj-labs/mcp-for-argocd](https://github.com/argoproj-labs/mcp-for-argocd)

Tools available:
- `list_applications` - List all ArgoCD applications
- `get_application` - Get detailed application info
- `sync_application` - Trigger application sync
- `get_application_status` - Check sync status

Example queries:
```
"List all ArgoCD applications"
"What's the sync status of the benchmark-workloads app?"
"Show me details of the istio-config application"
```

### Helm MCP Server

**Source**: [mcp-server-helm on PyPI](https://pypi.org/project/mcp-server-helm/)

Tools available:
- `helm_search` - Search for charts in repositories
- `helm_show_values` - Display chart values
- `helm_show_chart` - Display chart metadata
- `helm_repo_list` - List configured repositories
- `helm_repo_add` - Add a new repository

Example queries:
```
"Search for istio charts"
"Show me the default values for the prometheus chart"
"What Helm repositories are configured?"
```

### LitmusChaos MCP Server

**Source**: [litmuschaos/litmus-mcp-server](https://github.com/litmuschaos/litmus-mcp-server)

Tools available:
- `list_experiments` - List chaos experiments
- `run_experiment` - Execute a chaos experiment
- `stop_experiment` - Stop a running experiment
- `get_experiment_status` - Check experiment status
- `list_infrastructures` - List chaos infrastructures
- `list_probes` - List chaos probes

Example queries:
```
"List all available chaos experiments"
"Run pod-delete experiment on frontend pods"
"What's the status of the network-latency experiment?"
```

## Usage with Claude Code

Once the MCP servers are configured in `.mcp.json`, Claude Code can automatically use them. Example interactions:

### Kubernetes Operations
```
You: "Show me all pods that are not running in the benchmark namespace"
Claude: [Uses kubernetes MCP to list pods and filter by status]
```

### Performance Analysis
```
You: "What's the average latency overhead when Istio is enabled?"
Claude: [Uses prometheus MCP to query istio_request_duration metrics]
```

### GitOps Deployment
```
You: "Deploy the latest benchmark workloads"
Claude: [Uses argocd MCP to sync the application]
```

### Chaos Engineering
```
You: "Test resilience by killing random pods in the mesh"
Claude: [Uses litmuschaos MCP to run pod-delete experiment]
```

## Security Considerations

1. **Read-Only Mode**: For Kubernetes MCP, use `--read-only` flag in production
2. **RBAC**: Create dedicated ServiceAccounts with minimal permissions
3. **Token Rotation**: Rotate ArgoCD and LitmusChaos tokens regularly
4. **Network Isolation**: Use `--network host` only when necessary

## Troubleshooting

### MCP Server Not Connecting

```bash
# Check if npx can find the package
npx -y kubernetes-mcp-server@latest --help

# Test Docker-based server
docker run --rm ghcr.io/pab1it0/prometheus-mcp-server:latest --help
```

### Authentication Errors

```bash
# Verify kubeconfig
kubectl cluster-info

# Test ArgoCD connection
argocd app list --server $ARGOCD_SERVER

# Verify Prometheus access
curl $PROMETHEUS_URL/api/v1/status/config
```

## References

- [Model Context Protocol Specification](https://modelcontextprotocol.io/)
- [CNCF Landscape](https://landscape.cncf.io/)
- [Kubernetes MCP Server Docs](https://github.com/containers/kubernetes-mcp-server)
- [Prometheus MCP Server](https://github.com/pab1it0/prometheus-mcp-server)
- [ArgoCD MCP Server](https://github.com/argoproj-labs/mcp-for-argocd)
- [LitmusChaos MCP Server](https://github.com/litmuschaos/litmus-mcp-server)
