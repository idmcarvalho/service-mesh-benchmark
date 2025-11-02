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
/// Key: stat_id (see STAT_* constants)
/// Value: u64 counter
#[map]
pub static STATS: HashMap<u32, u64> =
    HashMap::with_max_entries(16, 0);

// Stat IDs for STATS map
pub const STAT_TOTAL_EVENTS: u32 = 0;
pub const STAT_SEND_EVENTS: u32 = 1;
pub const STAT_RECV_EVENTS: u32 = 2;
pub const STAT_CLEANUP_EVENTS: u32 = 3;
pub const STAT_DROPPED_EVENTS: u32 = 4;
pub const STAT_INVALID_SOCKETS: u32 = 5;
pub const STAT_INVALID_LATENCY: u32 = 6;
