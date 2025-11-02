//! Shared data structures between kernel and userspace
//!
//! These structures must be repr(C) to ensure consistent memory layout
//! between eBPF programs and userspace code.

/// Connection tracking key (4-tuple)
///
/// Used to uniquely identify TCP connections in BPF maps.
/// All fields are in network byte order (big-endian).
#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct ConnectionKey {
    /// Source IP address (network byte order)
    pub saddr: u32,
    /// Destination IP address (network byte order)
    pub daddr: u32,
    /// Source port (network byte order)
    pub sport: u16,
    /// Destination port (network byte order)
    pub dport: u16,
}

/// Latency event data sent from kernel to userspace
///
/// Captures timing information for network operations.
#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct LatencyEvent {
    /// Connection identifier
    pub key: ConnectionKey,
    /// Timestamp when event occurred (nanoseconds)
    pub timestamp_ns: u64,
    /// Measured latency (nanoseconds)
    pub latency_ns: u64,
    /// Process ID that triggered the event
    pub pid: u32,
    /// Type of event (see EVENT_TYPE_* constants)
    pub event_type: u8,
    /// Padding for alignment
    pub _padding: [u8; 3],
}

/// Packet drop event data
///
/// Captures information about dropped packets for analysis.
#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct PacketDropEvent {
    /// Connection identifier
    pub key: ConnectionKey,
    /// Timestamp when drop occurred (nanoseconds)
    pub timestamp_ns: u64,
    /// Drop reason code
    pub drop_reason: u32,
    /// Drop location (see DROP_LOCATION_* constants)
    pub drop_location: u8,
    /// Protocol (IPPROTO_TCP, IPPROTO_UDP, etc.)
    pub protocol: u8,
    /// Padding for alignment
    pub _padding: [u8; 2],
}

/// Connection state tracking
///
/// Tracks TCP connection lifecycle events.
#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct ConnectionState {
    /// Connection identifier
    pub key: ConnectionKey,
    /// Timestamp when connection started (nanoseconds)
    pub start_time_ns: u64,
    /// Timestamp when connection closed (nanoseconds, 0 if still open)
    pub close_time_ns: u64,
    /// Connection state (see CONN_STATE_* constants)
    pub state: u8,
    /// Number of bytes sent
    pub bytes_sent: u64,
    /// Number of bytes received
    pub bytes_received: u64,
    /// Process ID
    pub pid: u32,
    /// Padding for alignment
    pub _padding: [u8; 4],
}

// Compile-time alignment checks
// These will fail to compile if alignment is wrong
const _: () = {
    // ConnectionKey alignment check
    assert!(core::mem::size_of::<ConnectionKey>() % core::mem::align_of::<ConnectionKey>() == 0);
    // LatencyEvent alignment check
    assert!(core::mem::size_of::<LatencyEvent>() % core::mem::align_of::<LatencyEvent>() == 0);
    // PacketDropEvent alignment check
    assert!(core::mem::size_of::<PacketDropEvent>() % core::mem::align_of::<PacketDropEvent>() == 0);
    // ConnectionState alignment check
    assert!(core::mem::size_of::<ConnectionState>() % core::mem::align_of::<ConnectionState>() == 0);
};

// Implement Aya's Pod trait for userspace usage
#[cfg(feature = "userspace")]
mod userspace_impls {
    use super::*;

    // Pod trait implementations for reading from perf buffers in userspace
    unsafe impl aya::Pod for ConnectionKey {}
    unsafe impl aya::Pod for LatencyEvent {}
    unsafe impl aya::Pod for PacketDropEvent {}
    unsafe impl aya::Pod for ConnectionState {}
}
