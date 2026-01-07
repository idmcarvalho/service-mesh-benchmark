"""Analysis modules for service mesh benchmarking."""

from src.analysis.cost_analysis import (
    CloudPricing,
    CloudProvider,
    CostComparison,
    InfrastructureCosts,
    OperationalCosts,
    ResourceUsage,
    ROIAnalysis,
    TCOAnalysis,
    calculate_roi,
    calculate_tco,
    compare_mesh_costs,
)
from src.analysis.statistical_analysis import (
    ANOVAResult,
    DescriptiveStatistics,
    OutlierAnalysis,
    StatisticalComparison,
    calculate_descriptive_statistics,
    calculate_statistical_power,
    compare_multiple_meshes,
    compare_two_samples,
    detect_outliers_iqr,
    detect_outliers_zscore,
    generate_statistical_report,
    perform_normality_test,
)

__all__ = [
    # Statistical analysis
    "DescriptiveStatistics",
    "StatisticalComparison",
    "ANOVAResult",
    "OutlierAnalysis",
    "calculate_descriptive_statistics",
    "compare_two_samples",
    "compare_multiple_meshes",
    "detect_outliers_iqr",
    "detect_outliers_zscore",
    "perform_normality_test",
    "calculate_statistical_power",
    "generate_statistical_report",
    # Cost analysis
    "CloudProvider",
    "CloudPricing",
    "ResourceUsage",
    "OperationalCosts",
    "InfrastructureCosts",
    "TCOAnalysis",
    "ROIAnalysis",
    "CostComparison",
    "calculate_tco",
    "calculate_roi",
    "compare_mesh_costs",
]
