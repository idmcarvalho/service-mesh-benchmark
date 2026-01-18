//! Shared constants for eBPF probes
//!
//! These constants are used by both kernel and userspace programs
//! to ensure consistency in behavior and limits.

// ============================================================================
// BPF Map Sizes
// ============================================================================

/// Maximum number of concurrent connections to track
pub const MAX_CONNECTIONS: u32 = 10240;

/// Maximum number of events in perf buffer
pub const MAX_EVENTS: u32 = 1024;

/// Maximum number of packet drop events to track
pub const MAX_PACKET_DROPS: u32 = 4096;

// ============================================================================
// Event Types (for LatencyEvent.event_type)
// ============================================================================

/// Event triggered by tcp_sendmsg kprobe
pub const EVENT_TYPE_SEND: u8 = 0;

/// Event triggered by tcp_recvmsg kprobe
pub const EVENT_TYPE_RECV: u8 = 1;

/// Event triggered by tcp_cleanup_rbuf kprobe
pub const EVENT_TYPE_CLEANUP: u8 = 2;

// ============================================================================
// Connection States (for ConnectionState.state)
// ============================================================================

/// Connection is being established
pub const CONN_STATE_CONNECTING: u8 = 0;

/// Connection is established and active
pub const CONN_STATE_ESTABLISHED: u8 = 1;

/// Connection is being closed
pub const CONN_STATE_CLOSING: u8 = 2;

/// Connection is fully closed
pub const CONN_STATE_CLOSED: u8 = 3;

// ============================================================================
// Drop Locations (for PacketDropEvent.drop_location)
// ============================================================================

/// Packet dropped at TC (Traffic Control) layer
pub const DROP_LOCATION_TC: u8 = 0;

/// Packet dropped at XDP (eXpress Data Path) layer
pub const DROP_LOCATION_XDP: u8 = 1;

/// Packet dropped by netfilter/iptables
pub const DROP_LOCATION_NETFILTER: u8 = 2;

/// Packet dropped in network stack
pub const DROP_LOCATION_STACK: u8 = 3;

/// Packet dropped by application
pub const DROP_LOCATION_APP: u8 = 4;

// ============================================================================
// Latency Thresholds
// ============================================================================

/// Maximum latency to consider valid (60 seconds in nanoseconds)
/// Latencies above this are likely measurement errors
pub const MAX_LATENCY_NS: u64 = 60_000_000_000;

/// Minimum latency to consider valid (1 microsecond in nanoseconds)
/// Latencies below this are likely measurement errors
pub const MIN_LATENCY_NS: u64 = 1_000;

// ============================================================================
// Histogram Buckets (in microseconds)
// ============================================================================

/// Histogram bucket boundary: 0-1ms
pub const HISTOGRAM_BUCKET_1MS: u64 = 1_000;

/// Histogram bucket boundary: 1-5ms
pub const HISTOGRAM_BUCKET_5MS: u64 = 5_000;

/// Histogram bucket boundary: 5-10ms
pub const HISTOGRAM_BUCKET_10MS: u64 = 10_000;

/// Histogram bucket boundary: 10-50ms
pub const HISTOGRAM_BUCKET_50MS: u64 = 50_000;

/// Histogram bucket boundary: 50-100ms
pub const HISTOGRAM_BUCKET_100MS: u64 = 100_000;

// ============================================================================
// Sampling
// ============================================================================

/// Default sampling rate (1 = capture all events)
pub const DEFAULT_SAMPLE_RATE: u32 = 1;

/// Maximum sampling rate (capture 1 in N events)
pub const MAX_SAMPLE_RATE: u32 = 1000;

// ============================================================================
// Protocol Numbers (from linux/in.h)
// ============================================================================

/// TCP protocol number
pub const IPPROTO_TCP: u8 = 6;

/// UDP protocol number
pub const IPPROTO_UDP: u8 = 17;

/// ICMP protocol number
pub const IPPROTO_ICMP: u8 = 1;

// ============================================================================
// Port Ranges
// ============================================================================

/// Well-known port range start
pub const PORT_WELLKNOWN_START: u16 = 0;

/// Well-known port range end
pub const PORT_WELLKNOWN_END: u16 = 1023;

/// Registered port range start
pub const PORT_REGISTERED_START: u16 = 1024;

/// Registered port range end
pub const PORT_REGISTERED_END: u16 = 49151;

/// Dynamic/private port range start
pub const PORT_DYNAMIC_START: u16 = 49152;

/// Dynamic/private port range end
pub const PORT_DYNAMIC_END: u16 = 65535;

// ============================================================================
// Statistics Counter Indices (for STATS map)
// ============================================================================

/// Total number of events processed
pub const STAT_TOTAL_EVENTS: u32 = 0;

/// Number of send events (tcp_sendmsg)
pub const STAT_SEND_EVENTS: u32 = 1;

/// Number of receive events (tcp_recvmsg)
pub const STAT_RECV_EVENTS: u32 = 2;

/// Number of cleanup events (tcp_cleanup_rbuf)
pub const STAT_CLEANUP_EVENTS: u32 = 3;

/// Number of packet drop events
pub const STAT_PACKET_DROPS: u32 = 4;

/// Number of invalid socket operations
pub const STAT_INVALID_SOCKETS: u32 = 5;

/// Number of invalid latency measurements
pub const STAT_INVALID_LATENCY: u32 = 6;

/// Number of connections opened
pub const STAT_CONNECTIONS_OPENED: u32 = 7;

/// Number of connections closed
pub const STAT_CONNECTIONS_CLOSED: u32 = 8;

/// Number of TCP state transitions
pub const STAT_STATE_TRANSITIONS: u32 = 9;

/// Number of XDP packets processed
pub const STAT_XDP_PACKETS: u32 = 10;

/// Number of XDP IPv4 packets
pub const STAT_XDP_IPV4_PACKETS: u32 = 11;

/// Number of XDP TCP packets
pub const STAT_XDP_TCP_PACKETS: u32 = 12;

/// Number of XDP UDP packets
pub const STAT_XDP_UDP_PACKETS: u32 = 13;

/// Number of XDP ICMP packets
pub const STAT_XDP_ICMP_PACKETS: u32 = 14;

/// Number of XDP other protocol packets
pub const STAT_XDP_OTHER_PACKETS: u32 = 15;

/// Total number of statistics counters
pub const MAX_STATS: u32 = 16;
