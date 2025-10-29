//! Metrics collection and aggregation
//!
//! Aggregates latency events from the kernel and computes statistics.

use crate::types::*;
use std::collections::HashMap;

/// Metrics collector for aggregating latency events
#[derive(Default)]
pub struct MetricsCollector {
    /// All latency samples (for percentile calculation)
    all_latencies: Vec<f64>,
    /// Per-connection latency samples
    connection_latencies: HashMap<String, Vec<f64>>,
    /// Latency histogram
    histogram: LatencyHistogram,
    /// Event type breakdown
    event_types: EventTypeBreakdown,
    /// Total number of events processed
    total_events: u64,
}

impl MetricsCollector {
    /// Create a new metrics collector
    pub fn new() -> Self {
        Self::default()
    }

    /// Add a latency event to the collector
    ///
    /// # Arguments
    ///
    /// * `event` - Latency event from the eBPF program
    pub fn add_event(&mut self, event: &LatencyEvent) {
        // Convert nanoseconds to microseconds for easier handling
        let latency_us = event.latency_ns as f64 / 1000.0;

        // Add to global latencies
        self.all_latencies.push(latency_us);

        // Add to per-connection latencies
        let conn_str = connection_key_to_string(&event.key);
        self.connection_latencies
            .entry(conn_str)
            .or_insert_with(Vec::new)
            .push(latency_us);

        // Update histogram
        self.histogram.add_sample(latency_us);

        // Track event types
        match event.event_type {
            probe_common::constants::EVENT_TYPE_SEND => self.event_types.tcp_sendmsg += 1,
            probe_common::constants::EVENT_TYPE_RECV => self.event_types.tcp_recvmsg += 1,
            probe_common::constants::EVENT_TYPE_CLEANUP => self.event_types.tcp_cleanup_rbuf += 1,
            _ => {}
        }

        self.total_events += 1;
    }

    /// Generate aggregated metrics
    ///
    /// # Arguments
    ///
    /// * `elapsed_secs` - Duration of collection period in seconds
    ///
    /// # Returns
    ///
    /// LatencyMetrics with aggregated statistics
    pub fn generate_metrics(&self, elapsed_secs: u64) -> LatencyMetrics {
        // Calculate percentiles across all connections
        let percentiles = calculate_percentiles(self.all_latencies.clone());

        // Generate per-connection metrics
        let connection_metrics: HashMap<String, ConnectionMetrics> = self
            .connection_latencies
            .iter()
            .map(|(key, samples)| {
                let sum: f64 = samples.iter().sum();
                let avg = sum / samples.len() as f64;
                let min = samples
                    .iter()
                    .cloned()
                    .fold(f64::INFINITY, f64::min);
                let max = samples
                    .iter()
                    .cloned()
                    .fold(f64::NEG_INFINITY, f64::max);
                let std_dev = calculate_std_dev(samples, avg);

                // Parse source and destination from key
                let parts: Vec<&str> = key.split(" -> ").collect();

                (
                    key.clone(),
                    ConnectionMetrics {
                        source: parts[0].to_string(),
                        destination: parts.get(1).unwrap_or(&"unknown").to_string(),
                        events: samples.len() as u64,
                        min_latency_us: min,
                        max_latency_us: max,
                        avg_latency_us: avg,
                        std_dev_us: std_dev,
                    },
                )
            })
            .collect();

        LatencyMetrics {
            timestamp: chrono::Utc::now().to_rfc3339(),
            duration_seconds: elapsed_secs,
            total_events: self.total_events,
            connections: connection_metrics,
            histogram: self.histogram.clone(),
            percentiles,
            event_type_breakdown: self.event_types.clone(),
        }
    }

    /// Get current event count
    pub fn event_count(&self) -> u64 {
        self.total_events
    }

    /// Get number of unique connections
    pub fn connection_count(&self) -> usize {
        self.connection_latencies.len()
    }

    /// Get histogram reference
    pub fn histogram(&self) -> &LatencyHistogram {
        &self.histogram
    }

    /// Get event type breakdown reference
    pub fn event_types(&self) -> &EventTypeBreakdown {
        &self.event_types
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use probe_common::types::ConnectionKey;

    #[test]
    fn test_collector_basic() {
        let mut collector = MetricsCollector::new();

        let key = ConnectionKey {
            saddr: 0x0100007f, // 127.0.0.1 in network byte order
            daddr: 0x0100007f,
            sport: 0x5000,     // Port 80 in network byte order
            dport: 0x5000,
        };

        let event = LatencyEvent {
            key,
            timestamp_ns: 1000000,
            latency_ns: 500000,  // 500 microseconds
            pid: 1234,
            event_type: probe_common::constants::EVENT_TYPE_RECV,
            _padding: [0; 3],
        };

        collector.add_event(&event);

        assert_eq!(collector.event_count(), 1);
        assert_eq!(collector.connection_count(), 1);
    }

    #[test]
    fn test_histogram() {
        let mut collector = MetricsCollector::new();

        let key = ConnectionKey {
            saddr: 0x0100007f,
            daddr: 0x0100007f,
            sport: 0x5000,
            dport: 0x5000,
        };

        // Add events in different buckets
        let latencies = vec![500, 2000, 7000, 30000, 75000, 150000]; // in microseconds

        for (i, &latency_us) in latencies.iter().enumerate() {
            let event = LatencyEvent {
                key,
                timestamp_ns: (i as u64 + 1) * 1000000,
                latency_ns: latency_us * 1000, // Convert to nanoseconds
                pid: 1234,
                event_type: probe_common::constants::EVENT_TYPE_RECV,
                _padding: [0; 3],
            };
            collector.add_event(&event);
        }

        let histogram = collector.histogram();
        assert_eq!(histogram.bucket_0_1ms, 1);
        assert_eq!(histogram.bucket_1_5ms, 1);
        assert_eq!(histogram.bucket_5_10ms, 1);
        assert_eq!(histogram.bucket_10_50ms, 1);
        assert_eq!(histogram.bucket_50_100ms, 1);
        assert_eq!(histogram.bucket_100ms_plus, 1);
    }
}
