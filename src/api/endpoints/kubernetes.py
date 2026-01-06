"""Kubernetes integration endpoints."""

from typing import Any, Dict, List

from fastapi import APIRouter, HTTPException, status
from kubernetes import client, config as k8s_config

from src.api.config import MESH_COMPONENTS
from src.tests.models import MeshType

router = APIRouter(prefix="/kubernetes", tags=["Kubernetes"])


@router.get("/namespaces")
async def list_namespaces() -> List[str]:
    """List Kubernetes namespaces."""
    try:
        k8s_config.load_kube_config()
        v1 = client.CoreV1Api()
        namespaces = v1.list_namespace()
        return [ns.metadata.name for ns in namespaces.items]
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Failed to connect to Kubernetes: {str(e)}",
        )


@router.get("/services/{namespace}")
async def list_services(namespace: str) -> List[Dict[str, Any]]:
    """List services in a namespace."""
    try:
        k8s_config.load_kube_config()
        v1 = client.CoreV1Api()
        services = v1.list_namespaced_service(namespace)

        return [
            {
                "name": svc.metadata.name,
                "type": svc.spec.type,
                "cluster_ip": svc.spec.cluster_ip,
                "ports": [
                    {"port": port.port, "protocol": port.protocol, "name": port.name}
                    for port in (svc.spec.ports or [])
                ],
            }
            for svc in services.items
        ]
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Failed to list services: {str(e)}",
        )


@router.get("/pods/{namespace}")
async def list_pods(namespace: str, label_selector: str = "") -> List[Dict[str, Any]]:
    """List pods in a namespace."""
    try:
        k8s_config.load_kube_config()
        v1 = client.CoreV1Api()
        pods = v1.list_namespaced_pod(namespace, label_selector=label_selector)

        return [
            {
                "name": pod.metadata.name,
                "status": pod.status.phase,
                "node": pod.spec.node_name,
                "ip": pod.status.pod_ip,
                "ready": all(
                    c.ready
                    for c in (pod.status.container_statuses or [])
                ),
                "containers": [c.name for c in pod.spec.containers],
            }
            for pod in pods.items
        ]
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Failed to list pods: {str(e)}",
        )


@router.get("/mesh-status/{namespace}")
async def get_mesh_status(namespace: str, mesh_type: MeshType) -> Dict[str, Any]:
    """Get service mesh status in a namespace."""
    try:
        k8s_config.load_kube_config()
        v1 = client.CoreV1Api()

        # Check for mesh-specific components
        components_found = []
        mesh_components = MESH_COMPONENTS.get(mesh_type.value, [])

        for component in mesh_components:
            try:
                pods = v1.list_namespaced_pod(namespace, label_selector=f"app={component}")
                if pods.items:
                    components_found.append(component)
            except Exception:
                pass

        return {
            "mesh_type": mesh_type.value,
            "namespace": namespace,
            "installed": len(components_found) > 0,
            "components": components_found,
            "healthy": len(components_found) == len(mesh_components),
        }

    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Failed to get mesh status: {str(e)}",
        )


@router.get("/nodes")
async def list_nodes() -> List[Dict[str, Any]]:
    """List Kubernetes nodes."""
    try:
        k8s_config.load_kube_config()
        v1 = client.CoreV1Api()
        nodes = v1.list_node()

        return [
            {
                "name": node.metadata.name,
                "status": next(
                    (c.type for c in node.status.conditions if c.status == "True"),
                    "Unknown",
                ),
                "cpu_capacity": node.status.capacity.get("cpu"),
                "memory_capacity": node.status.capacity.get("memory"),
                "kernel_version": node.status.node_info.kernel_version,
                "container_runtime": node.status.node_info.container_runtime_version,
            }
            for node in nodes.items
        ]
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Failed to list nodes: {str(e)}",
        )
