"""Cost analysis module for service mesh benchmarking.

This module provides TCO (Total Cost of Ownership) analysis, ROI calculations,
and cost comparisons across different service mesh implementations.
"""

from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field, computed_field


class CloudProvider(str, Enum):
    """Supported cloud providers."""

    OCI = "oci"
    AWS = "aws"
    GCP = "gcp"
    AZURE = "azure"
    BARE_METAL = "bare_metal"


class CloudPricing(BaseModel):
    """Cloud provider pricing configuration."""

    provider: CloudProvider
    region: str = Field(description="Cloud region (e.g., us-east-1, us-ashburn-1)")

    # Compute pricing (per hour)
    compute_price_per_cpu_hour: float = Field(ge=0, description="Price per vCPU hour")
    compute_price_per_gb_memory_hour: float = Field(
        ge=0, description="Price per GB memory hour"
    )

    # Network pricing
    network_egress_price_per_gb: float = Field(ge=0, description="Price per GB egress")
    network_ingress_price_per_gb: float = Field(
        default=0.0, ge=0, description="Price per GB ingress (usually free)"
    )

    # Load balancer pricing
    load_balancer_price_per_hour: float = Field(ge=0, description="Load balancer hourly cost")
    load_balancer_price_per_gb: float = Field(
        default=0.0, ge=0, description="Load balancer data processed cost"
    )

    # Storage pricing (if applicable)
    storage_price_per_gb_month: float = Field(
        default=0.0, ge=0, description="Block storage price per GB/month"
    )

    # Discounts
    commitment_discount_percent: float = Field(
        default=0.0, ge=0, le=100, description="Discount for 1-year/3-year commitment"
    )


# Default pricing configurations
DEFAULT_PRICING = {
    CloudProvider.OCI: CloudPricing(
        provider=CloudProvider.OCI,
        region="us-ashburn-1",
        compute_price_per_cpu_hour=0.01,  # Ampere A1 pricing
        compute_price_per_gb_memory_hour=0.0015,
        network_egress_price_per_gb=0.0085,
        load_balancer_price_per_hour=0.0125,
        storage_price_per_gb_month=0.0255,
    ),
    CloudProvider.AWS: CloudPricing(
        provider=CloudProvider.AWS,
        region="us-east-1",
        compute_price_per_cpu_hour=0.0416,  # t3.medium pricing
        compute_price_per_gb_memory_hour=0.0052,
        network_egress_price_per_gb=0.09,
        load_balancer_price_per_hour=0.0225,
        storage_price_per_gb_month=0.10,
    ),
    CloudProvider.GCP: CloudPricing(
        provider=CloudProvider.GCP,
        region="us-central1",
        compute_price_per_cpu_hour=0.033174,  # n1-standard pricing
        compute_price_per_gb_memory_hour=0.004446,
        network_egress_price_per_gb=0.12,
        load_balancer_price_per_hour=0.025,
        storage_price_per_gb_month=0.04,
    ),
    CloudProvider.AZURE: CloudPricing(
        provider=CloudProvider.AZURE,
        region="eastus",
        compute_price_per_cpu_hour=0.0416,  # B2s pricing
        compute_price_per_gb_memory_hour=0.0052,
        network_egress_price_per_gb=0.087,
        load_balancer_price_per_hour=0.025,
        storage_price_per_gb_month=0.05,
    ),
}


class ResourceUsage(BaseModel):
    """Resource usage metrics for cost calculation."""

    # Compute resources
    cpu_millicores: float = Field(ge=0, description="CPU usage in millicores")
    memory_mb: float = Field(ge=0, description="Memory usage in MB")

    # Network usage
    network_egress_gb: float = Field(default=0.0, ge=0, description="Network egress in GB")
    network_ingress_gb: float = Field(default=0.0, ge=0, description="Network ingress in GB")

    # Storage
    storage_gb: float = Field(default=0.0, ge=0, description="Storage used in GB")

    # Load balancer
    uses_load_balancer: bool = Field(default=False, description="Whether LB is used")
    load_balancer_data_processed_gb: float = Field(
        default=0.0, ge=0, description="Data processed by LB"
    )

    @computed_field
    @property
    def cpu_cores(self) -> float:
        """Convert millicores to cores."""
        return self.cpu_millicores / 1000.0

    @computed_field
    @property
    def memory_gb(self) -> float:
        """Convert MB to GB."""
        return self.memory_mb / 1024.0


class OperationalCosts(BaseModel):
    """Operational overhead costs beyond infrastructure."""

    # Engineering time
    setup_hours: float = Field(ge=0, description="Hours to setup and configure")
    monthly_maintenance_hours: float = Field(
        ge=0, description="Hours per month for maintenance"
    )
    hourly_engineer_rate: float = Field(ge=0, description="Hourly rate for engineers")

    # Additional costs
    training_cost_one_time: float = Field(
        default=0.0, ge=0, description="One-time training costs"
    )
    support_cost_monthly: float = Field(
        default=0.0, ge=0, description="Monthly support/license costs"
    )

    # Debugging/troubleshooting overhead
    debugging_hours_monthly: float = Field(
        default=0.0, ge=0, description="Average monthly debugging hours"
    )

    @computed_field
    @property
    def setup_cost(self) -> float:
        """Calculate one-time setup cost."""
        return self.setup_hours * self.hourly_engineer_rate + self.training_cost_one_time

    @computed_field
    @property
    def monthly_operational_cost(self) -> float:
        """Calculate monthly operational cost."""
        return (
            (self.monthly_maintenance_hours + self.debugging_hours_monthly) *
            self.hourly_engineer_rate +
            self.support_cost_monthly
        )


class InfrastructureCosts(BaseModel):
    """Infrastructure costs calculated from resource usage and pricing."""

    resource_usage: ResourceUsage
    pricing: CloudPricing
    hours_per_month: float = Field(default=730, description="Average hours per month")

    @computed_field
    @property
    def monthly_compute_cost(self) -> float:
        """Calculate monthly compute costs (CPU + memory)."""
        cpu_cost = (
            self.resource_usage.cpu_cores *
            self.pricing.compute_price_per_cpu_hour *
            self.hours_per_month
        )

        memory_cost = (
            self.resource_usage.memory_gb *
            self.pricing.compute_price_per_gb_memory_hour *
            self.hours_per_month
        )

        return cpu_cost + memory_cost

    @computed_field
    @property
    def monthly_network_cost(self) -> float:
        """Calculate monthly network costs."""
        egress_cost = (
            self.resource_usage.network_egress_gb *
            self.pricing.network_egress_price_per_gb
        )

        ingress_cost = (
            self.resource_usage.network_ingress_gb *
            self.pricing.network_ingress_price_per_gb
        )

        return egress_cost + ingress_cost

    @computed_field
    @property
    def monthly_load_balancer_cost(self) -> float:
        """Calculate monthly load balancer costs."""
        if not self.resource_usage.uses_load_balancer:
            return 0.0

        fixed_cost = (
            self.pricing.load_balancer_price_per_hour *
            self.hours_per_month
        )

        data_cost = (
            self.resource_usage.load_balancer_data_processed_gb *
            self.pricing.load_balancer_price_per_gb
        )

        return fixed_cost + data_cost

    @computed_field
    @property
    def monthly_storage_cost(self) -> float:
        """Calculate monthly storage costs."""
        return (
            self.resource_usage.storage_gb *
            self.pricing.storage_price_per_gb_month
        )

    @computed_field
    @property
    def monthly_total(self) -> float:
        """Calculate total monthly infrastructure cost."""
        total = (
            self.monthly_compute_cost +
            self.monthly_network_cost +
            self.monthly_load_balancer_cost +
            self.monthly_storage_cost
        )

        # Apply commitment discount if applicable
        discount_multiplier = 1.0 - (self.pricing.commitment_discount_percent / 100.0)
        return total * discount_multiplier


class TCOAnalysis(BaseModel):
    """Total Cost of Ownership analysis for a service mesh."""

    mesh_name: str = Field(description="Service mesh name (e.g., 'istio', 'cilium')")
    infrastructure_costs: InfrastructureCosts
    operational_costs: OperationalCosts

    # Performance metrics for ROI calculation
    performance_improvement_percent: float = Field(
        default=0.0, description="Performance improvement vs baseline (%)"
    )
    resource_savings_percent: float = Field(
        default=0.0, description="Resource savings vs baseline (%)"
    )

    # Metadata
    analysis_date: datetime = Field(default_factory=datetime.utcnow)
    baseline_comparison: bool = Field(
        default=False, description="Whether this is the baseline"
    )

    @computed_field
    @property
    def monthly_total_cost(self) -> float:
        """Calculate total monthly cost (infrastructure + operational)."""
        return (
            self.infrastructure_costs.monthly_total +
            self.operational_costs.monthly_operational_cost
        )

    @computed_field
    @property
    def annual_total_cost(self) -> float:
        """Calculate total annual cost."""
        return self.monthly_total_cost * 12 + self.operational_costs.setup_cost

    @computed_field
    @property
    def three_year_total_cost(self) -> float:
        """Calculate 3-year total cost."""
        return self.monthly_total_cost * 36 + self.operational_costs.setup_cost

    def get_cost_breakdown(self) -> Dict[str, float]:
        """Get detailed cost breakdown."""
        return {
            "monthly_compute": self.infrastructure_costs.monthly_compute_cost,
            "monthly_network": self.infrastructure_costs.monthly_network_cost,
            "monthly_load_balancer": self.infrastructure_costs.monthly_load_balancer_cost,
            "monthly_storage": self.infrastructure_costs.monthly_storage_cost,
            "monthly_infrastructure_total": self.infrastructure_costs.monthly_total,
            "monthly_operational": self.operational_costs.monthly_operational_cost,
            "monthly_total": self.monthly_total_cost,
            "setup_cost_one_time": self.operational_costs.setup_cost,
            "annual_total": self.annual_total_cost,
            "three_year_total": self.three_year_total_cost,
        }


class ROIAnalysis(BaseModel):
    """Return on Investment analysis comparing mesh to baseline."""

    baseline_tco: TCOAnalysis
    mesh_tco: TCOAnalysis

    # Value of performance improvements
    performance_value_monthly: float = Field(
        default=0.0,
        ge=0,
        description="Estimated monthly value of performance improvements",
    )

    # Business impact
    downtime_reduction_percent: float = Field(
        default=0.0, ge=0, le=100, description="Reduction in downtime %"
    )
    downtime_cost_per_hour: float = Field(
        default=0.0, ge=0, description="Cost of downtime per hour"
    )

    @computed_field
    @property
    def additional_monthly_cost(self) -> float:
        """Calculate additional monthly cost vs baseline."""
        return self.mesh_tco.monthly_total_cost - self.baseline_tco.monthly_total_cost

    @computed_field
    @property
    def additional_annual_cost(self) -> float:
        """Calculate additional annual cost vs baseline."""
        return self.additional_monthly_cost * 12

    @computed_field
    @property
    def monthly_downtime_savings(self) -> float:
        """Calculate monthly savings from reduced downtime."""
        # Assume 730 hours/month average
        hours_per_month = 730
        baseline_downtime_hours = hours_per_month * 0.001  # Assume 0.1% baseline
        reduction = baseline_downtime_hours * (self.downtime_reduction_percent / 100.0)

        return reduction * self.downtime_cost_per_hour

    @computed_field
    @property
    def monthly_net_benefit(self) -> float:
        """Calculate net monthly benefit (value - cost)."""
        total_value = self.performance_value_monthly + self.monthly_downtime_savings
        return total_value - self.additional_monthly_cost

    @computed_field
    @property
    def annual_net_benefit(self) -> float:
        """Calculate net annual benefit."""
        return self.monthly_net_benefit * 12

    @computed_field
    @property
    def payback_period_months(self) -> Optional[float]:
        """Calculate payback period in months."""
        if self.monthly_net_benefit <= 0:
            return None  # Never pays back

        initial_investment = self.mesh_tco.operational_costs.setup_cost
        return initial_investment / self.monthly_net_benefit

    @computed_field
    @property
    def roi_percent(self) -> float:
        """Calculate ROI percentage for first year."""
        total_investment = (
            self.additional_annual_cost +
            self.mesh_tco.operational_costs.setup_cost
        )

        if total_investment == 0:
            return 0.0

        total_return = self.annual_net_benefit + total_investment
        return (total_return / total_investment - 1.0) * 100

    @computed_field
    @property
    def three_year_roi_percent(self) -> float:
        """Calculate ROI percentage for 3 years."""
        total_investment = (
            self.additional_annual_cost * 3 +
            self.mesh_tco.operational_costs.setup_cost
        )

        if total_investment == 0:
            return 0.0

        total_return = self.annual_net_benefit * 3 + total_investment
        return (total_return / total_investment - 1.0) * 100


class CostComparison(BaseModel):
    """Cost comparison across multiple service meshes."""

    baseline_tco: TCOAnalysis
    mesh_tcos: List[TCOAnalysis]

    analysis_date: datetime = Field(default_factory=datetime.utcnow)
    currency: str = Field(default="USD", description="Currency code")

    def get_best_value_mesh(self) -> Optional[str]:
        """Determine which mesh provides best value (lowest cost + best performance).

        Uses a simple scoring: cost_score + performance_score.
        Lower cost is better, higher performance is better.
        """
        if not self.mesh_tcos:
            return None

        best_mesh = None
        best_score = float("inf")

        for mesh_tco in self.mesh_tcos:
            # Normalize cost (lower is better, scale 0-100)
            cost_vs_baseline = (
                mesh_tco.monthly_total_cost /
                self.baseline_tco.monthly_total_cost
            )
            cost_score = cost_vs_baseline * 50  # Weight cost at 50%

            # Normalize performance (higher is better, scale 0-50)
            perf_score = 50 - (mesh_tco.performance_improvement_percent / 100.0 * 50)

            total_score = cost_score + perf_score

            if total_score < best_score:
                best_score = total_score
                best_mesh = mesh_tco.mesh_name

        return best_mesh

    def get_lowest_cost_mesh(self) -> Optional[str]:
        """Get the mesh with lowest monthly cost."""
        if not self.mesh_tcos:
            return None

        return min(
            self.mesh_tcos,
            key=lambda x: x.monthly_total_cost
        ).mesh_name

    def get_best_performance_mesh(self) -> Optional[str]:
        """Get the mesh with best performance improvement."""
        if not self.mesh_tcos:
            return None

        return max(
            self.mesh_tcos,
            key=lambda x: x.performance_improvement_percent
        ).mesh_name

    def generate_comparison_table(self) -> List[Dict[str, Any]]:
        """Generate comparison table data."""
        table = []

        # Baseline row
        table.append({
            "mesh": "Baseline (no mesh)",
            "monthly_cost": f"${self.baseline_tco.monthly_total_cost:.2f}",
            "annual_cost": f"${self.baseline_tco.annual_total_cost:.2f}",
            "performance_improvement": "0%",
            "cost_delta": "$0.00",
        })

        # Mesh rows
        for mesh_tco in self.mesh_tcos:
            delta = mesh_tco.monthly_total_cost - self.baseline_tco.monthly_total_cost

            table.append({
                "mesh": mesh_tco.mesh_name.capitalize(),
                "monthly_cost": f"${mesh_tco.monthly_total_cost:.2f}",
                "annual_cost": f"${mesh_tco.annual_total_cost:.2f}",
                "performance_improvement": f"{mesh_tco.performance_improvement_percent:+.1f}%",
                "cost_delta": f"${delta:+.2f}",
            })

        return table


def calculate_tco(
    mesh_name: str,
    resource_usage: ResourceUsage,
    operational_costs: OperationalCosts,
    cloud_provider: CloudProvider = CloudProvider.OCI,
    pricing: Optional[CloudPricing] = None,
    performance_improvement_percent: float = 0.0,
    baseline: bool = False,
) -> TCOAnalysis:
    """Calculate Total Cost of Ownership for a service mesh.

    Args:
        mesh_name: Name of the service mesh.
        resource_usage: Resource usage metrics.
        operational_costs: Operational overhead costs.
        cloud_provider: Cloud provider (defaults to OCI).
        pricing: Custom pricing (uses defaults if not provided).
        performance_improvement_percent: Performance improvement vs baseline.
        baseline: Whether this is the baseline measurement.

    Returns:
        TCOAnalysis object with complete cost breakdown.
    """
    if pricing is None:
        pricing = DEFAULT_PRICING.get(cloud_provider, DEFAULT_PRICING[CloudProvider.OCI])

    infra_costs = InfrastructureCosts(
        resource_usage=resource_usage,
        pricing=pricing,
    )

    return TCOAnalysis(
        mesh_name=mesh_name,
        infrastructure_costs=infra_costs,
        operational_costs=operational_costs,
        performance_improvement_percent=performance_improvement_percent,
        baseline_comparison=baseline,
    )


def compare_mesh_costs(
    baseline_tco: TCOAnalysis,
    mesh_tcos: List[TCOAnalysis],
) -> CostComparison:
    """Create cost comparison across multiple meshes.

    Args:
        baseline_tco: TCO analysis for baseline (no mesh).
        mesh_tcos: List of TCO analyses for different meshes.

    Returns:
        CostComparison object with analysis.
    """
    return CostComparison(
        baseline_tco=baseline_tco,
        mesh_tcos=mesh_tcos,
    )


def calculate_roi(
    baseline_tco: TCOAnalysis,
    mesh_tco: TCOAnalysis,
    performance_value_monthly: float = 0.0,
    downtime_reduction_percent: float = 0.0,
    downtime_cost_per_hour: float = 0.0,
) -> ROIAnalysis:
    """Calculate Return on Investment for a service mesh.

    Args:
        baseline_tco: TCO for baseline configuration.
        mesh_tco: TCO for service mesh configuration.
        performance_value_monthly: Estimated monthly value of performance improvements.
        downtime_reduction_percent: Reduction in downtime percentage.
        downtime_cost_per_hour: Cost of downtime per hour.

    Returns:
        ROIAnalysis with payback period, ROI%, and net benefit.
    """
    return ROIAnalysis(
        baseline_tco=baseline_tco,
        mesh_tco=mesh_tco,
        performance_value_monthly=performance_value_monthly,
        downtime_reduction_percent=downtime_reduction_percent,
        downtime_cost_per_hour=downtime_cost_per_hour,
    )
