//! Metrics exporters
//!
//! Provides different exporters for metrics (JSON, Prometheus, etc.)

use crate::types::LatencyMetrics;
use anyhow::{Context, Result};
use std::{fs::File, io::Write, path::PathBuf};

/// Trait for metrics exporters
pub trait MetricsExporter {
    /// Export metrics
    ///
    /// # Arguments
    ///
    /// * `metrics` - Aggregated metrics to export
    ///
    /// # Returns
    ///
    /// Result indicating success or failure
    fn export(&self, metrics: &LatencyMetrics) -> Result<()>;
}

/// Export format type
#[derive(Debug, Clone, Copy)]
pub enum ExporterType {
    /// JSON format
    Json,
    /// Prometheus format
    Prometheus,
    /// InfluxDB line protocol
    Influx,
}

/// JSON exporter
pub struct JsonExporter {
    output_path: PathBuf,
    pretty: bool,
}

impl JsonExporter {
    /// Create a new JSON exporter
    ///
    /// # Arguments
    ///
    /// * `output_path` - Path to output file
    /// * `pretty` - Enable pretty-printing
    pub fn new(output_path: PathBuf, pretty: bool) -> Self {
        Self {
            output_path,
            pretty,
        }
    }
}

impl MetricsExporter for JsonExporter {
    fn export(&self, metrics: &LatencyMetrics) -> Result<()> {
        let json = if self.pretty {
            serde_json::to_string_pretty(metrics)?
        } else {
            serde_json::to_string(metrics)?
        };

        let mut file = File::create(&self.output_path)
            .with_context(|| format!("Failed to create output file: {:?}", self.output_path))?;

        file.write_all(json.as_bytes())
            .with_context(|| format!("Failed to write to output file: {:?}", self.output_path))?;

        Ok(())
    }
}

/// Prometheus exporter
pub struct PrometheusExporter {
    output_path: PathBuf,
}

impl PrometheusExporter {
    /// Create a new Prometheus exporter
    ///
    /// # Arguments
    ///
    /// * `output_path` - Path to output file
    pub fn new(output_path: PathBuf) -> Self {
        Self { output_path }
    }

    /// Convert metrics to Prometheus format
    fn to_prometheus_format(metrics: &LatencyMetrics) -> String {
        let mut output = String::new();

        // Total events
        output.push_str("# HELP latency_probe_events_total Total number of latency events\n");
        output.push_str("# TYPE latency_probe_events_total counter\n");
        output.push_str(&format!("latency_probe_events_total {}\n", metrics.total_events));
        output.push('\n');

        // Duration
        output.push_str("# HELP latency_probe_duration_seconds Duration of collection period\n");
        output.push_str("# TYPE latency_probe_duration_seconds gauge\n");
        output.push_str(&format!("latency_probe_duration_seconds {}\n", metrics.duration_seconds));
        output.push('\n');

        // Percentiles
        output.push_str("# HELP latency_probe_latency_microseconds Latency percentiles in microseconds\n");
        output.push_str("# TYPE latency_probe_latency_microseconds gauge\n");
        output.push_str(&format!("latency_probe_latency_microseconds{{percentile=\"0.50\"}} {}\n", metrics.percentiles.p50));
        output.push_str(&format!("latency_probe_latency_microseconds{{percentile=\"0.75\"}} {}\n", metrics.percentiles.p75));
        output.push_str(&format!("latency_probe_latency_microseconds{{percentile=\"0.90\"}} {}\n", metrics.percentiles.p90));
        output.push_str(&format!("latency_probe_latency_microseconds{{percentile=\"0.95\"}} {}\n", metrics.percentiles.p95));
        output.push_str(&format!("latency_probe_latency_microseconds{{percentile=\"0.99\"}} {}\n", metrics.percentiles.p99));
        output.push_str(&format!("latency_probe_latency_microseconds{{percentile=\"0.999\"}} {}\n", metrics.percentiles.p999));
        output.push('\n');

        // Histogram
        output.push_str("# HELP latency_probe_histogram_bucket Latency histogram buckets\n");
        output.push_str("# TYPE latency_probe_histogram_bucket gauge\n");
        output.push_str(&format!("latency_probe_histogram_bucket{{le=\"1000\"}} {}\n", metrics.histogram.bucket_0_1ms));
        output.push_str(&format!("latency_probe_histogram_bucket{{le=\"5000\"}} {}\n", metrics.histogram.bucket_1_5ms));
        output.push_str(&format!("latency_probe_histogram_bucket{{le=\"10000\"}} {}\n", metrics.histogram.bucket_5_10ms));
        output.push_str(&format!("latency_probe_histogram_bucket{{le=\"50000\"}} {}\n", metrics.histogram.bucket_10_50ms));
        output.push_str(&format!("latency_probe_histogram_bucket{{le=\"100000\"}} {}\n", metrics.histogram.bucket_50_100ms));
        output.push_str(&format!("latency_probe_histogram_bucket{{le=\"+Inf\"}} {}\n", metrics.histogram.bucket_100ms_plus));
        output.push('\n');

        // Event types
        output.push_str("# HELP latency_probe_events_by_type Events broken down by type\n");
        output.push_str("# TYPE latency_probe_events_by_type counter\n");
        output.push_str(&format!("latency_probe_events_by_type{{type=\"tcp_sendmsg\"}} {}\n", metrics.event_type_breakdown.tcp_sendmsg));
        output.push_str(&format!("latency_probe_events_by_type{{type=\"tcp_recvmsg\"}} {}\n", metrics.event_type_breakdown.tcp_recvmsg));
        output.push_str(&format!("latency_probe_events_by_type{{type=\"tcp_cleanup_rbuf\"}} {}\n", metrics.event_type_breakdown.tcp_cleanup_rbuf));
        output.push('\n');

        // Connection count
        output.push_str("# HELP latency_probe_connections_total Total number of unique connections\n");
        output.push_str("# TYPE latency_probe_connections_total gauge\n");
        output.push_str(&format!("latency_probe_connections_total {}\n", metrics.connections.len()));
        output.push('\n');

        output
    }
}

impl MetricsExporter for PrometheusExporter {
    fn export(&self, metrics: &LatencyMetrics) -> Result<()> {
        let prometheus_data = Self::to_prometheus_format(metrics);

        let mut file = File::create(&self.output_path)
            .with_context(|| format!("Failed to create output file: {:?}", self.output_path))?;

        file.write_all(prometheus_data.as_bytes())
            .with_context(|| format!("Failed to write to output file: {:?}", self.output_path))?;

        Ok(())
    }
}

/// InfluxDB line protocol exporter
pub struct InfluxExporter {
    output_path: PathBuf,
    measurement: String,
}

impl InfluxExporter {
    /// Create a new InfluxDB exporter
    ///
    /// # Arguments
    ///
    /// * `output_path` - Path to output file
    /// * `measurement` - Measurement name for InfluxDB
    pub fn new(output_path: PathBuf, measurement: String) -> Self {
        Self {
            output_path,
            measurement,
        }
    }

    /// Convert metrics to InfluxDB line protocol
    fn to_influx_format(metrics: &LatencyMetrics, measurement: &str) -> String {
        let mut output = String::new();
        let timestamp = chrono::Utc::now().timestamp_nanos_opt().unwrap_or(0);

        // Global metrics
        output.push_str(&format!(
            "{},type=summary total_events={}i,duration_seconds={}i,connections={}i {}\n",
            measurement,
            metrics.total_events,
            metrics.duration_seconds,
            metrics.connections.len(),
            timestamp
        ));

        // Percentiles
        output.push_str(&format!(
            "{},type=percentiles p50={},p75={},p90={},p95={},p99={},p999={} {}\n",
            measurement,
            metrics.percentiles.p50,
            metrics.percentiles.p75,
            metrics.percentiles.p90,
            metrics.percentiles.p95,
            metrics.percentiles.p99,
            metrics.percentiles.p999,
            timestamp
        ));

        // Histogram
        output.push_str(&format!(
            "{},type=histogram bucket_0_1ms={}i,bucket_1_5ms={}i,bucket_5_10ms={}i,bucket_10_50ms={}i,bucket_50_100ms={}i,bucket_100ms_plus={}i {}\n",
            measurement,
            metrics.histogram.bucket_0_1ms,
            metrics.histogram.bucket_1_5ms,
            metrics.histogram.bucket_5_10ms,
            metrics.histogram.bucket_10_50ms,
            metrics.histogram.bucket_50_100ms,
            metrics.histogram.bucket_100ms_plus,
            timestamp
        ));

        // Event types
        output.push_str(&format!(
            "{},type=events tcp_sendmsg={}i,tcp_recvmsg={}i,tcp_cleanup_rbuf={}i {}\n",
            measurement,
            metrics.event_type_breakdown.tcp_sendmsg,
            metrics.event_type_breakdown.tcp_recvmsg,
            metrics.event_type_breakdown.tcp_cleanup_rbuf,
            timestamp
        ));

        output
    }
}

impl MetricsExporter for InfluxExporter {
    fn export(&self, metrics: &LatencyMetrics) -> Result<()> {
        let influx_data = Self::to_influx_format(metrics, &self.measurement);

        let mut file = File::create(&self.output_path)
            .with_context(|| format!("Failed to create output file: {:?}", self.output_path))?;

        file.write_all(influx_data.as_bytes())
            .with_context(|| format!("Failed to write to output file: {:?}", self.output_path))?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    fn create_test_metrics() -> LatencyMetrics {
        use crate::types::*;

        LatencyMetrics {
            timestamp: "2025-01-01T00:00:00Z".to_string(),
            duration_seconds: 60,
            total_events: 1000,
            connections: HashMap::new(),
            histogram: LatencyHistogram::default(),
            percentiles: Percentiles {
                p50: 100.0,
                p75: 200.0,
                p90: 300.0,
                p95: 400.0,
                p99: 500.0,
                p999: 600.0,
            },
            event_type_breakdown: EventTypeBreakdown::default(),
        }
    }

    #[test]
    fn test_prometheus_format() {
        let metrics = create_test_metrics();
        let prometheus = PrometheusExporter::to_prometheus_format(&metrics);

        assert!(prometheus.contains("latency_probe_events_total 1000"));
        assert!(prometheus.contains("latency_probe_duration_seconds 60"));
        assert!(prometheus.contains("percentile=\"0.50\""));
    }

    #[test]
    fn test_influx_format() {
        let metrics = create_test_metrics();
        let influx = InfluxExporter::to_influx_format(&metrics, "latency");

        assert!(influx.contains("latency,type=summary"));
        assert!(influx.contains("total_events=1000i"));
        assert!(influx.contains("p50=100"));
    }
}
