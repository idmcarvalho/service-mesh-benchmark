"""Statistical analysis module for service mesh benchmarks.

This module provides statistical tests, confidence intervals, effect sizes,
and other statistical measures for comparing service mesh performance.
"""

from typing import Any, Dict, List, Optional, Tuple

import numpy as np
import pandas as pd
from pydantic import BaseModel, Field, computed_field
from scipy import stats


class DescriptiveStatistics(BaseModel):
    """Descriptive statistics for a dataset."""

    mean: float = Field(description="Arithmetic mean")
    median: float = Field(description="Median (50th percentile)")
    std_dev: float = Field(description="Standard deviation")
    variance: float = Field(description="Variance")
    min_value: float = Field(description="Minimum value")
    max_value: float = Field(description="Maximum value")
    sample_size: int = Field(description="Number of samples", ge=1)

    # Percentiles
    p25: float = Field(description="25th percentile")
    p75: float = Field(description="75th percentile")
    p90: float = Field(description="90th percentile")
    p95: float = Field(description="95th percentile")
    p99: float = Field(description="99th percentile")

    # Additional metrics
    coefficient_of_variation: float = Field(description="Coefficient of variation (CV)")
    standard_error: float = Field(description="Standard error of the mean")

    @computed_field
    @property
    def confidence_interval_95(self) -> Tuple[float, float]:
        """Calculate 95% confidence interval for the mean."""
        margin_of_error = 1.96 * self.standard_error
        return (self.mean - margin_of_error, self.mean + margin_of_error)

    @computed_field
    @property
    def interquartile_range(self) -> float:
        """Calculate interquartile range (IQR)."""
        return self.p75 - self.p25


class StatisticalComparison(BaseModel):
    """Statistical comparison between two samples (baseline vs mesh)."""

    baseline_stats: DescriptiveStatistics
    mesh_stats: DescriptiveStatistics

    # Hypothesis testing
    t_statistic: float = Field(description="Student's t-statistic")
    p_value: float = Field(description="P-value for statistical significance")
    degrees_of_freedom: int = Field(description="Degrees of freedom")

    # Effect size
    cohens_d: float = Field(description="Cohen's d effect size")

    # Test metadata
    test_type: str = Field(default="two_sample_t_test", description="Type of statistical test")
    alpha: float = Field(default=0.05, description="Significance level")

    @computed_field
    @property
    def is_significant(self) -> bool:
        """Determine if the difference is statistically significant."""
        return self.p_value < self.alpha

    @computed_field
    @property
    def effect_size_interpretation(self) -> str:
        """Interpret the effect size using Cohen's guidelines."""
        abs_d = abs(self.cohens_d)
        if abs_d < 0.2:
            return "negligible"
        elif abs_d < 0.5:
            return "small"
        elif abs_d < 0.8:
            return "medium"
        else:
            return "large"

    @computed_field
    @property
    def percent_difference(self) -> float:
        """Calculate percentage difference between means."""
        if self.baseline_stats.mean == 0:
            return 0.0
        return ((self.mesh_stats.mean - self.baseline_stats.mean) /
                self.baseline_stats.mean * 100)

    @computed_field
    @property
    def confidence_intervals_overlap(self) -> bool:
        """Check if 95% confidence intervals overlap."""
        baseline_ci = self.baseline_stats.confidence_interval_95
        mesh_ci = self.mesh_stats.confidence_interval_95

        return not (baseline_ci[1] < mesh_ci[0] or mesh_ci[1] < baseline_ci[0])


class ANOVAResult(BaseModel):
    """Results from ANOVA test comparing multiple service meshes."""

    f_statistic: float = Field(description="F-statistic from ANOVA")
    p_value: float = Field(description="P-value for overall significance")
    degrees_of_freedom_between: int = Field(description="Between-groups df")
    degrees_of_freedom_within: int = Field(description="Within-groups df")

    group_statistics: Dict[str, DescriptiveStatistics] = Field(
        description="Statistics for each group (mesh)"
    )

    alpha: float = Field(default=0.05, description="Significance level")

    @computed_field
    @property
    def is_significant(self) -> bool:
        """Determine if at least one group differs significantly."""
        return self.p_value < self.alpha

    @computed_field
    @property
    def eta_squared(self) -> float:
        """Calculate eta-squared (effect size for ANOVA)."""
        # This is a simplified calculation
        # In practice, you'd calculate from sum of squares
        return 0.0  # Placeholder - implement based on actual data


class OutlierAnalysis(BaseModel):
    """Analysis of outliers in the dataset."""

    outliers_count: int = Field(description="Number of outliers detected", ge=0)
    outliers_percent: float = Field(description="Percentage of data that are outliers", ge=0)
    outlier_indices: List[int] = Field(description="Indices of outlier values")
    outlier_values: List[float] = Field(description="Outlier values")

    method: str = Field(description="Method used for outlier detection")
    lower_bound: float = Field(description="Lower bound for outlier detection")
    upper_bound: float = Field(description="Upper bound for outlier detection")


def calculate_descriptive_statistics(data: List[float]) -> DescriptiveStatistics:
    """Calculate comprehensive descriptive statistics for a dataset.

    Args:
        data: List of numeric values.

    Returns:
        DescriptiveStatistics object with all calculated metrics.

    Raises:
        ValueError: If data is empty or contains invalid values.
    """
    if not data:
        raise ValueError("Data cannot be empty")

    arr = np.array(data)

    if np.any(np.isnan(arr)) or np.any(np.isinf(arr)):
        raise ValueError("Data contains NaN or infinite values")

    mean_val = float(np.mean(arr))
    std_val = float(np.std(arr, ddof=1))  # Sample std dev

    return DescriptiveStatistics(
        mean=mean_val,
        median=float(np.median(arr)),
        std_dev=std_val,
        variance=float(np.var(arr, ddof=1)),
        min_value=float(np.min(arr)),
        max_value=float(np.max(arr)),
        sample_size=len(arr),
        p25=float(np.percentile(arr, 25)),
        p75=float(np.percentile(arr, 75)),
        p90=float(np.percentile(arr, 90)),
        p95=float(np.percentile(arr, 95)),
        p99=float(np.percentile(arr, 99)),
        coefficient_of_variation=std_val / mean_val if mean_val != 0 else 0.0,
        standard_error=std_val / np.sqrt(len(arr)),
    )


def compare_two_samples(
    baseline: List[float],
    mesh: List[float],
    alpha: float = 0.05,
    equal_variance: bool = True,
) -> StatisticalComparison:
    """Perform statistical comparison between baseline and mesh performance.

    Uses Student's t-test (or Welch's t-test if variances are unequal) to
    determine if there's a statistically significant difference.

    Args:
        baseline: Baseline performance measurements.
        mesh: Service mesh performance measurements.
        alpha: Significance level (default: 0.05).
        equal_variance: Whether to assume equal variances (default: True).

    Returns:
        StatisticalComparison object with test results.

    Raises:
        ValueError: If samples are invalid or too small.
    """
    if len(baseline) < 2 or len(mesh) < 2:
        raise ValueError("Each sample must have at least 2 observations")

    baseline_stats = calculate_descriptive_statistics(baseline)
    mesh_stats = calculate_descriptive_statistics(mesh)

    # Perform t-test
    t_stat, p_val = stats.ttest_ind(
        baseline,
        mesh,
        equal_var=equal_variance
    )

    # Calculate Cohen's d (effect size)
    pooled_std = np.sqrt(
        ((len(baseline) - 1) * baseline_stats.variance +
         (len(mesh) - 1) * mesh_stats.variance) /
        (len(baseline) + len(mesh) - 2)
    )
    cohens_d = (mesh_stats.mean - baseline_stats.mean) / pooled_std if pooled_std > 0 else 0.0

    # Degrees of freedom
    if equal_variance:
        df = len(baseline) + len(mesh) - 2
    else:
        # Welch-Satterthwaite equation
        s1_sq = baseline_stats.variance
        s2_sq = mesh_stats.variance
        n1 = len(baseline)
        n2 = len(mesh)
        df = int(
            (s1_sq/n1 + s2_sq/n2)**2 /
            ((s1_sq/n1)**2/(n1-1) + (s2_sq/n2)**2/(n2-1))
        )

    test_name = "two_sample_t_test" if equal_variance else "welch_t_test"

    return StatisticalComparison(
        baseline_stats=baseline_stats,
        mesh_stats=mesh_stats,
        t_statistic=float(t_stat),
        p_value=float(p_val),
        degrees_of_freedom=df,
        cohens_d=cohens_d,
        test_type=test_name,
        alpha=alpha,
    )


def compare_multiple_meshes(
    mesh_data: Dict[str, List[float]],
    alpha: float = 0.05,
) -> ANOVAResult:
    """Perform one-way ANOVA to compare multiple service meshes.

    Args:
        mesh_data: Dictionary mapping mesh names to their performance data.
        alpha: Significance level (default: 0.05).

    Returns:
        ANOVAResult object with ANOVA results.

    Raises:
        ValueError: If fewer than 2 groups or invalid data.
    """
    if len(mesh_data) < 2:
        raise ValueError("Need at least 2 groups for ANOVA")

    # Prepare data for ANOVA
    groups = list(mesh_data.values())

    # Perform one-way ANOVA
    f_stat, p_val = stats.f_oneway(*groups)

    # Calculate descriptive statistics for each group
    group_stats = {
        name: calculate_descriptive_statistics(data)
        for name, data in mesh_data.items()
    }

    # Calculate degrees of freedom
    k = len(mesh_data)  # Number of groups
    n = sum(len(data) for data in mesh_data.values())  # Total observations
    df_between = k - 1
    df_within = n - k

    return ANOVAResult(
        f_statistic=float(f_stat),
        p_value=float(p_val),
        degrees_of_freedom_between=df_between,
        degrees_of_freedom_within=df_within,
        group_statistics=group_stats,
        alpha=alpha,
    )


def detect_outliers_iqr(
    data: List[float],
    multiplier: float = 1.5,
) -> OutlierAnalysis:
    """Detect outliers using the Interquartile Range (IQR) method.

    Outliers are defined as values outside [Q1 - multiplier*IQR, Q3 + multiplier*IQR].

    Args:
        data: List of numeric values.
        multiplier: IQR multiplier (default: 1.5 for typical outliers, 3.0 for extreme).

    Returns:
        OutlierAnalysis object with detected outliers.
    """
    arr = np.array(data)

    q1 = np.percentile(arr, 25)
    q3 = np.percentile(arr, 75)
    iqr = q3 - q1

    lower_bound = q1 - multiplier * iqr
    upper_bound = q3 + multiplier * iqr

    outlier_mask = (arr < lower_bound) | (arr > upper_bound)
    outlier_indices = np.where(outlier_mask)[0].tolist()
    outlier_values = arr[outlier_mask].tolist()

    return OutlierAnalysis(
        outliers_count=len(outlier_indices),
        outliers_percent=len(outlier_indices) / len(data) * 100 if data else 0.0,
        outlier_indices=outlier_indices,
        outlier_values=outlier_values,
        method="iqr",
        lower_bound=float(lower_bound),
        upper_bound=float(upper_bound),
    )


def detect_outliers_zscore(
    data: List[float],
    threshold: float = 3.0,
) -> OutlierAnalysis:
    """Detect outliers using the Z-score method.

    Outliers are defined as values with |Z-score| > threshold.

    Args:
        data: List of numeric values.
        threshold: Z-score threshold (default: 3.0).

    Returns:
        OutlierAnalysis object with detected outliers.
    """
    arr = np.array(data)

    mean = np.mean(arr)
    std = np.std(arr)

    if std == 0:
        return OutlierAnalysis(
            outliers_count=0,
            outliers_percent=0.0,
            outlier_indices=[],
            outlier_values=[],
            method="zscore",
            lower_bound=mean,
            upper_bound=mean,
        )

    z_scores = np.abs((arr - mean) / std)
    outlier_mask = z_scores > threshold
    outlier_indices = np.where(outlier_mask)[0].tolist()
    outlier_values = arr[outlier_mask].tolist()

    lower_bound = mean - threshold * std
    upper_bound = mean + threshold * std

    return OutlierAnalysis(
        outliers_count=len(outlier_indices),
        outliers_percent=len(outlier_indices) / len(data) * 100 if data else 0.0,
        outlier_indices=outlier_indices,
        outlier_values=outlier_values,
        method="zscore",
        lower_bound=float(lower_bound),
        upper_bound=float(upper_bound),
    )


def perform_normality_test(data: List[float]) -> Tuple[bool, float]:
    """Test if data follows a normal distribution using Shapiro-Wilk test.

    Args:
        data: List of numeric values.

    Returns:
        Tuple of (is_normal, p_value).
    """
    if len(data) < 3:
        raise ValueError("Need at least 3 samples for normality test")

    stat, p_value = stats.shapiro(data)
    is_normal = p_value > 0.05

    return is_normal, float(p_value)


def calculate_statistical_power(
    effect_size: float,
    sample_size: int,
    alpha: float = 0.05,
) -> float:
    """Calculate statistical power for detecting an effect.

    Args:
        effect_size: Expected effect size (Cohen's d).
        sample_size: Sample size per group.
        alpha: Significance level.

    Returns:
        Statistical power (1 - beta).
    """
    from scipy.stats import norm

    # This is a simplified calculation for two-sample t-test
    # For production, consider using statsmodels.stats.power

    critical_value = norm.ppf(1 - alpha / 2)

    # Non-centrality parameter
    ncp = effect_size * np.sqrt(sample_size / 2)

    # Power calculation
    power = 1 - norm.cdf(critical_value - ncp) + norm.cdf(-critical_value - ncp)

    return float(power)


def generate_statistical_report(
    baseline: List[float],
    mesh_results: Dict[str, List[float]],
    metric_name: str = "latency",
    alpha: float = 0.05,
) -> Dict[str, Any]:
    """Generate comprehensive statistical report comparing baseline vs meshes.

    Args:
        baseline: Baseline measurements.
        mesh_results: Dictionary of mesh name to measurements.
        metric_name: Name of the metric being compared.
        alpha: Significance level.

    Returns:
        Dictionary with comprehensive statistical analysis.
    """
    report = {
        "metric": metric_name,
        "alpha": alpha,
        "baseline_statistics": calculate_descriptive_statistics(baseline).model_dump(),
        "pairwise_comparisons": {},
        "anova_result": None,
        "outlier_analysis": {},
    }

    # Pairwise comparisons: baseline vs each mesh
    for mesh_name, mesh_data in mesh_results.items():
        try:
            comparison = compare_two_samples(baseline, mesh_data, alpha=alpha)
            report["pairwise_comparisons"][mesh_name] = comparison.model_dump()
        except ValueError as e:
            report["pairwise_comparisons"][mesh_name] = {"error": str(e)}

    # ANOVA if multiple meshes
    if len(mesh_results) > 1:
        all_data = {"baseline": baseline, **mesh_results}
        try:
            anova = compare_multiple_meshes(all_data, alpha=alpha)
            report["anova_result"] = anova.model_dump()
        except ValueError as e:
            report["anova_result"] = {"error": str(e)}

    # Outlier analysis
    try:
        baseline_outliers = detect_outliers_iqr(baseline)
        report["outlier_analysis"]["baseline"] = baseline_outliers.model_dump()

        for mesh_name, mesh_data in mesh_results.items():
            mesh_outliers = detect_outliers_iqr(mesh_data)
            report["outlier_analysis"][mesh_name] = mesh_outliers.model_dump()
    except Exception as e:
        report["outlier_analysis"] = {"error": str(e)}

    return report
