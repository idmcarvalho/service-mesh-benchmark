//! Userspace type definitions
//!
//! Defines the data structures used by the userspace program for
//! metrics collection and export.
//!
//! ## Organization
//!
//! This module separates kernel and userspace types:
//! - **Kernel Types**: Types shared with eBPF programs (from probe_common)
//! - **Userspace Types**: Types used only in userspace for aggregation and export

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

// ============================================================================
// Kernel Types (from eBPF programs)
// ============================================================================

pub mod kernel {
    //! Types shared between kernel eBPF programs and userspace
    //!
    //! These are re-exported from the probe-common crate and must
    //! maintain binary compatibility with the eBPF programs.

    pub use probe_common::types::{ConnectionKey, LatencyEvent, PacketDropEvent, ConnectionState};
    pub use probe_common::constants;
}

// Re-export commonly used kernel types at module level for convenience
pub use kernel::{ConnectionKey, LatencyEvent};

/// Aggregated metrics for export
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct LatencyMetrics {
    /// ISO 8601 timestamp when metrics were collected
    pub timestamp: String,
    /// Duration of collection period in seconds
    pub duration_seconds: u64,
    /// Total number of events captured
    pub total_events: u64,
    /// Per-connection metrics
    pub connections: HashMap<String, ConnectionMetrics>,
    /// Latency histogram across all connections
    pub histogram: LatencyHistogram,
    /// Latency percentiles across all connections
    pub percentiles: Percentiles,
    /// Breakdown by event type
    pub event_type_breakdown: EventTypeBreakdown,
    /// Packet drop statistics
    pub packet_drops: PacketDropStats,
    /// Connection state statistics
    pub connection_states: ConnectionStateStats,
}

/// Metrics for a single connection
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct ConnectionMetrics {
    /// Source address:port
    pub source: String,
    /// Destination address:port
    pub destination: String,
    /// Number of events for this connection
    pub events: u64,
    /// Minimum latency in microseconds
    pub min_latency_us: f64,
    /// Maximum latency in microseconds
    pub max_latency_us: f64,
    /// Average latency in microseconds
    pub avg_latency_us: f64,
    /// Standard deviation in microseconds
    pub std_dev_us: f64,
}

/// Latency histogram buckets
#[derive(Serialize, Deserialize, Debug, Default, Clone)]
pub struct LatencyHistogram {
    /// 0-1ms bucket
    #[serde(rename = "0-1ms")]
    pub bucket_0_1ms: u64,
    /// 1-5ms bucket
    #[serde(rename = "1-5ms")]
    pub bucket_1_5ms: u64,
    /// 5-10ms bucket
    #[serde(rename = "5-10ms")]
    pub bucket_5_10ms: u64,
    /// 10-50ms bucket
    #[serde(rename = "10-50ms")]
    pub bucket_10_50ms: u64,
    /// 50-100ms bucket
    #[serde(rename = "50-100ms")]
    pub bucket_50_100ms: u64,
    /// 100ms+ bucket
    #[serde(rename = "100ms+")]
    pub bucket_100ms_plus: u64,
}

impl LatencyHistogram {
    /// Add a sample to the appropriate bucket
    ///
    /// # Arguments
    ///
    /// * `latency_us` - Latency in microseconds
    pub fn add_sample(&mut self, latency_us: f64) {
        match latency_us {
            l if l < 1000.0 => self.bucket_0_1ms += 1,
            l if l < 5000.0 => self.bucket_1_5ms += 1,
            l if l < 10000.0 => self.bucket_5_10ms += 1,
            l if l < 50000.0 => self.bucket_10_50ms += 1,
            l if l < 100000.0 => self.bucket_50_100ms += 1,
            _ => self.bucket_100ms_plus += 1,
        }
    }

    /// Get total count across all buckets
    pub fn total_count(&self) -> u64 {
        self.bucket_0_1ms
            + self.bucket_1_5ms
            + self.bucket_5_10ms
            + self.bucket_10_50ms
            + self.bucket_50_100ms
            + self.bucket_100ms_plus
    }
}

/// Latency percentiles
#[derive(Serialize, Deserialize, Debug, Default, Clone)]
pub struct Percentiles {
    /// 50th percentile (median)
    pub p50: f64,
    /// 75th percentile
    pub p75: f64,
    /// 90th percentile
    pub p90: f64,
    /// 95th percentile
    pub p95: f64,
    /// 99th percentile
    pub p99: f64,
    /// 99.9th percentile
    pub p999: f64,
}

/// Event type breakdown
#[derive(Serialize, Deserialize, Debug, Default, Clone)]
pub struct EventTypeBreakdown {
    /// Count of tcp_sendmsg events
    pub tcp_sendmsg: u64,
    /// Count of tcp_recvmsg events
    pub tcp_recvmsg: u64,
    /// Count of tcp_cleanup_rbuf events
    pub tcp_cleanup_rbuf: u64,
}

/// Packet drop statistics
#[derive(Serialize, Deserialize, Debug, Default, Clone)]
pub struct PacketDropStats {
    /// Total packet drops
    pub total_drops: u64,
    /// Drops by location
    pub drops_by_location: HashMap<String, u64>,
    /// Drops by protocol
    pub drops_by_protocol: HashMap<String, u64>,
    /// Per-connection drop counts
    pub connections: HashMap<String, u64>,
}

/// Connection state statistics
#[derive(Serialize, Deserialize, Debug, Default, Clone)]
pub struct ConnectionStateStats {
    /// Total connections opened
    pub total_opened: u64,
    /// Total connections closed
    pub total_closed: u64,
    /// Active connections (currently in state map)
    pub active_connections: u64,
    /// Average connection duration in seconds
    pub avg_duration_seconds: f64,
    /// Connection states breakdown
    pub states_breakdown: HashMap<String, u64>,
}

/// Calculate percentiles from a sorted vector of samples
///
/// # Arguments
///
/// * `samples` - Vector of latency values (will be sorted in place)
///
/// # Returns
///
/// Percentiles structure with p50, p75, p90, p95, p99, p999
pub fn calculate_percentiles(mut samples: Vec<f64>) -> Percentiles {
    if samples.is_empty() {
        return Percentiles::default();
    }

    samples.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let len = samples.len();

    let percentile = |p: usize| {
        let index = std::cmp::min((len * p / 100).saturating_sub(1), len - 1);
        samples[index]
    };

    Percentiles {
        p50: percentile(50),
        p75: percentile(75),
        p90: percentile(90),
        p95: percentile(95),
        p99: percentile(99),
        p999: {
            // Calculate 99.9th percentile (999 out of 1000)
            let index = std::cmp::min(((len * 999) / 1000).saturating_sub(1), len - 1);
            samples[index]
        },
    }
}

/// Calculate standard deviation
///
/// # Arguments
///
/// * `samples` - Slice of values
/// * `mean` - Mean of the values
///
/// # Returns
///
/// Standard deviation
pub fn calculate_std_dev(samples: &[f64], mean: f64) -> f64 {
    if samples.len() <= 1 {
        return 0.0;
    }

    let variance: f64 = samples
        .iter()
        .map(|x| (x - mean).powi(2))
        .sum::<f64>()
        / samples.len() as f64;
    variance.sqrt()
}

/// Convert ConnectionKey to string representation
///
/// # Arguments
///
/// * `key` - Connection key from eBPF
///
/// # Returns
///
/// String in format "saddr:sport -> daddr:dport"
pub fn connection_key_to_string(key: &ConnectionKey) -> String {
    use std::net::Ipv4Addr;

    let saddr = Ipv4Addr::from(u32::from_be(key.saddr));
    let daddr = Ipv4Addr::from(u32::from_be(key.daddr));

    format!(
        "{}:{} -> {}:{}",
        saddr,
        u16::from_be(key.sport),
        daddr,
        u16::from_be(key.dport)
    )
}
