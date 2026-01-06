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
    HashMap::with_max_entries(32, 0);

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

// Stat IDs for STATS map
pub const STAT_TOTAL_EVENTS: u32 = 0;
pub const STAT_SEND_EVENTS: u32 = 1;
pub const STAT_RECV_EVENTS: u32 = 2;
pub const STAT_CLEANUP_EVENTS: u32 = 3;
pub const STAT_DROPPED_EVENTS: u32 = 4;
pub const STAT_INVALID_SOCKETS: u32 = 5;
pub const STAT_INVALID_LATENCY: u32 = 6;
pub const STAT_PACKET_DROPS: u32 = 7;
pub const STAT_STATE_TRANSITIONS: u32 = 8;
pub const STAT_CONNECTIONS_OPENED: u32 = 9;
pub const STAT_CONNECTIONS_CLOSED: u32 = 10;
