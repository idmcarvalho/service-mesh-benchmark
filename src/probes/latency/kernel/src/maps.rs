//! BPF map definitions for latency tracking
//!
//! Defines the maps used for communication between kernel and userspace,
//! and for storing connection state.

use aya_ebpf::{
    macros::map,
    maps::{HashMap, PerfEventArray},
};
use probe_common::{types::*, constants::*};

/// Map to store connection start timestamps
///
/// Key: ConnectionKey (4-tuple)
/// Value: u64 timestamp in nanoseconds
///
/// This map tracks when we first see traffic for a connection,
/// allowing us to calculate latency on subsequent events.
#[map]
pub static CONNECTION_START: HashMap<ConnectionKey, u64> =
    HashMap::with_max_entries(MAX_CONNECTIONS, 0);

/// Perf event array to send latency events to userspace
///
/// Events are written to this map by kprobes and read by
/// the userspace program for aggregation and analysis.
#[map]
pub static EVENTS: PerfEventArray<LatencyEvent> =
    PerfEventArray::new(0);

/// Statistics counter map
///
/// Tracks various statistics for monitoring probe health.
/// Key: stat_id (see STAT_* constants in probe_common::constants)
/// Value: u64 counter
#[map]
pub static STATS: HashMap<u32, u64> =
    HashMap::with_max_entries(MAX_STATS, 0);

/// Perf event array for packet drop events
///
/// Events are written when packets are dropped in the kernel.
#[map]
pub static PACKET_DROPS: PerfEventArray<PacketDropEvent> =
    PerfEventArray::new(0);

/// Map to track connection states
///
/// Key: ConnectionKey (4-tuple)
/// Value: ConnectionState
///
/// Tracks the lifecycle of TCP connections.
#[map]
pub static CONNECTION_STATES: HashMap<ConnectionKey, ConnectionState> =
    HashMap::with_max_entries(MAX_CONNECTIONS, 0);

/// Map to track XDP-level connection statistics
///
/// Key: ConnectionKey (4-tuple)
/// Value: XdpConnStats
///
/// Tracks packet and byte counters at the XDP level for each connection.
/// This provides early packet visibility before the network stack.
#[map]
pub static XDP_CONN_STATS: HashMap<ConnectionKey, XdpConnStats> =
    HashMap::with_max_entries(MAX_CONNECTIONS, 0);
