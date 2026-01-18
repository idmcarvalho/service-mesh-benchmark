//! Kprobe and XDP handlers for TCP latency tracking
//!
//! Implements the actual eBPF programs that attach to kernel functions
//! and measure network latency, packet drops, and connection states.

use aya_ebpf::{
    macros::{kprobe, tracepoint, xdp},
    programs::{ProbeContext, XdpContext},
};
use aya_ebpf::bindings::xdp_action;
use probe_common::{constants::*, types::*};

use crate::{
    helpers::*,
    maps::*,
    socket_parser::*,
};

/// Track TCP send operations
///
/// Attached to: tcp_sendmsg
///
/// Records the timestamp when data is sent on a connection.
/// This timestamp is used later to calculate send-to-receive latency.
#[kprobe]
pub fn tcp_sendmsg(ctx: ProbeContext) -> u32 {
    match try_tcp_sendmsg(&ctx) {
        Ok(ret) => ret,
        Err(_) => 1,
    }
}

fn try_tcp_sendmsg(ctx: &ProbeContext) -> Result<u32, i64> {
    increment_stat(STAT_TOTAL_EVENTS);
    increment_stat(STAT_SEND_EVENTS);

    // Get socket structure from first argument
    let sock = get_sock_from_context(ctx)?;

    // Validate socket
    if !is_valid_socket(sock) {
        increment_stat(STAT_INVALID_SOCKETS);
        return Ok(0);
    }

    // Extract connection 4-tuple
    let key = match extract_connection_key(sock) {
        Ok(k) => k,
        Err(_) => {
            increment_stat(STAT_INVALID_SOCKETS);
            return Ok(0);
        }
    };

    // Record timestamp for this connection
    let timestamp = get_timestamp();

    unsafe {
        // Store the send timestamp
        // This will be used by tcp_recvmsg to calculate latency
        let _ = CONNECTION_START.insert(&key, &timestamp, 0);
    }

    // Optionally, send a "send" event to userspace for full tracing
    // (disabled by default to reduce overhead)
    // let event = create_latency_event(key, timestamp, 0, EVENT_TYPE_SEND);
    // unsafe {
    //     let _ = EVENTS.output(&ctx, &event, 0);
    // }

    Ok(0)
}

/// Track TCP receive operations
///
/// Attached to: tcp_recvmsg
///
/// Measures the latency from send to receive by looking up the
/// corresponding send timestamp and calculating the difference.
#[kprobe]
pub fn tcp_recvmsg(ctx: ProbeContext) -> u32 {
    match try_tcp_recvmsg(&ctx) {
        Ok(ret) => ret,
        Err(_) => 1,
    }
}

fn try_tcp_recvmsg(ctx: &ProbeContext) -> Result<u32, i64> {
    increment_stat(STAT_TOTAL_EVENTS);
    increment_stat(STAT_RECV_EVENTS);

    // Get socket structure from first argument
    let sock = get_sock_from_context(ctx)?;

    // Validate socket
    if !is_valid_socket(sock) {
        increment_stat(STAT_INVALID_SOCKETS);
        return Ok(0);
    }

    // Extract connection 4-tuple
    let key = match extract_connection_key(sock) {
        Ok(k) => k,
        Err(_) => {
            increment_stat(STAT_INVALID_SOCKETS);
            return Ok(0);
        }
    };

    let current_time = get_timestamp();

    // Look up start timestamp from CONNECTION_START map
    let start_time = unsafe {
        match CONNECTION_START.get(&key) {
            Some(ts) => *ts,
            None => {
                // No start time recorded, possibly the first event we see
                // Record current time for future measurements
                let _ = CONNECTION_START.insert(&key, &current_time, 0);
                return Ok(0);
            }
        }
    };

    // Calculate latency
    if current_time <= start_time {
        // Time went backwards? Skip this event
        return Ok(0);
    }

    let latency_ns = current_time - start_time;

    // Validate latency is within reasonable bounds
    if !is_valid_latency(latency_ns) {
        increment_stat(STAT_INVALID_LATENCY);
        return Ok(0);
    }

    // Create and send latency event to userspace
    let event = create_latency_event(key, current_time, latency_ns, EVENT_TYPE_RECV);

    unsafe {
        EVENTS.output(ctx, &event, 0);
        // Update the start time for the next measurement
        let _ = CONNECTION_START.insert(&key, &current_time, 0);
    }

    Ok(0)
}

/// Track TCP receive buffer cleanup
///
/// Attached to: tcp_cleanup_rbuf
///
/// This provides an additional measurement point for receive-side latency.
/// It's called when the receive buffer is being cleaned up after data
/// has been read by the application.
#[kprobe]
pub fn tcp_cleanup_rbuf(ctx: ProbeContext) -> u32 {
    match try_tcp_cleanup_rbuf(&ctx) {
        Ok(ret) => ret,
        Err(_) => 1,
    }
}

fn try_tcp_cleanup_rbuf(ctx: &ProbeContext) -> Result<u32, i64> {
    increment_stat(STAT_TOTAL_EVENTS);
    increment_stat(STAT_CLEANUP_EVENTS);

    // Get socket structure from first argument
    let sock = get_sock_from_context(ctx)?;

    // Validate socket
    if !is_valid_socket(sock) {
        increment_stat(STAT_INVALID_SOCKETS);
        return Ok(0);
    }

    // Extract connection 4-tuple
    let key = match extract_connection_key(sock) {
        Ok(k) => k,
        Err(_) => {
            increment_stat(STAT_INVALID_SOCKETS);
            return Ok(0);
        }
    };

    let current_time = get_timestamp();

    // Look up start timestamp
    let start_time = unsafe {
        match CONNECTION_START.get(&key) {
            Some(ts) => *ts,
            None => {
                // No start time, record it for future use
                let _ = CONNECTION_START.insert(&key, &current_time, 0);
                return Ok(0);
            }
        }
    };

    // Calculate latency
    if current_time <= start_time {
        return Ok(0);
    }

    let latency_ns = current_time - start_time;

    // Validate latency
    if !is_valid_latency(latency_ns) {
        increment_stat(STAT_INVALID_LATENCY);
        return Ok(0);
    }

    // Create and send cleanup event
    let event = create_latency_event(key, current_time, latency_ns, EVENT_TYPE_CLEANUP);

    unsafe {
        EVENTS.output(ctx, &event, 0);
        // Update timestamp for next measurement
        let _ = CONNECTION_START.insert(&key, &current_time, 0);
    }

    Ok(0)
}

// ============================================================================
// Packet Drop Tracking
// ============================================================================

/// Track TCP-specific packet drops
///
/// Attached to: tcp_drop
///
/// This kprobe captures TCP packets that are dropped by the kernel,
/// providing insight into connection reliability issues.
#[kprobe]
pub fn tcp_drop(ctx: ProbeContext) -> u32 {
    match try_tcp_drop(&ctx) {
        Ok(ret) => ret,
        Err(_) => 1,
    }
}

fn try_tcp_drop(ctx: &ProbeContext) -> Result<u32, i64> {
    increment_stat(STAT_TOTAL_EVENTS);
    increment_stat(STAT_PACKET_DROPS);

    // Get socket structure from first argument
    let sock = get_sock_from_context(ctx)?;

    if !is_valid_socket(sock) {
        return Ok(0);
    }

    // Extract connection 4-tuple
    let key = match extract_connection_key(sock) {
        Ok(k) => k,
        Err(_) => return Ok(0),
    };

    let timestamp = get_timestamp();

    // Create packet drop event
    let event = PacketDropEvent {
        key,
        timestamp_ns: timestamp,
        drop_reason: 0, // tcp_drop doesn't provide reason in older kernels
        drop_location: DROP_LOCATION_STACK,
        protocol: IPPROTO_TCP,
        _padding: [0; 2],
    };

    unsafe {
        let _ = PACKET_DROPS.output(ctx, &event, 0);
    }

    Ok(0)
}

/// Track general packet drops via tracepoint
///
/// Attached to: skb:kfree_skb tracepoint
///
/// This tracepoint captures all packet drops at the network stack level,
/// providing comprehensive drop tracking across all protocols.
#[tracepoint]
pub fn kfree_skb_tracepoint(ctx: ProbeContext) -> u32 {
    match try_kfree_skb(&ctx) {
        Ok(ret) => ret,
        Err(_) => 1,
    }
}

fn try_kfree_skb(ctx: &ProbeContext) -> Result<u32, i64> {
    increment_stat(STAT_TOTAL_EVENTS);
    increment_stat(STAT_PACKET_DROPS);

    // Tracepoint context provides different args than kprobe
    // For kfree_skb: arg0=skb, arg1=location, arg2=protocol

    // For now, we'll create a simplified drop event
    // In a production implementation, we'd parse the skb structure
    // to extract connection information

    let timestamp = get_timestamp();

    // Create a generic drop event
    // Note: Extracting full connection info from skb requires more complex parsing
    let event = PacketDropEvent {
        key: ConnectionKey {
            saddr: 0,
            daddr: 0,
            sport: 0,
            dport: 0,
        },
        timestamp_ns: timestamp,
        drop_reason: 0,
        drop_location: DROP_LOCATION_STACK,
        protocol: IPPROTO_TCP,
        _padding: [0; 2],
    };

    unsafe {
        let _ = PACKET_DROPS.output(ctx, &event, 0);
    }

    Ok(0)
}

// ============================================================================
// Connection State Tracking
// ============================================================================

/// Track TCP connection state changes
///
/// Attached to: tcp_set_state
///
/// Monitors TCP state machine transitions (ESTABLISHED, CLOSE, etc.)
/// to track connection lifecycle.
#[kprobe]
pub fn tcp_set_state(ctx: ProbeContext) -> u32 {
    match try_tcp_set_state(&ctx) {
        Ok(ret) => ret,
        Err(_) => 1,
    }
}

fn try_tcp_set_state(ctx: &ProbeContext) -> Result<u32, i64> {
    increment_stat(STAT_TOTAL_EVENTS);
    increment_stat(STAT_STATE_TRANSITIONS);

    // tcp_set_state(struct sock *sk, int state)
    // arg0: sock pointer
    // arg1: new state

    let sock = get_sock_from_context(ctx)?;

    if !is_valid_socket(sock) {
        return Ok(0);
    }

    let key = match extract_connection_key(sock) {
        Ok(k) => k,
        Err(_) => return Ok(0),
    };

    // Get the new state from arg1
    let new_state: i32 = ctx.arg(1).ok_or(-1)?;

    let timestamp = get_timestamp();
    let pid = get_pid();

    // Map TCP states to our simplified state model
    // TCP_ESTABLISHED = 1, TCP_CLOSE = 7, etc.
    let conn_state = match new_state {
        1 => {
            // TCP_ESTABLISHED
            increment_stat(STAT_CONNECTIONS_OPENED);
            CONN_STATE_ESTABLISHED
        }
        2..=6 => CONN_STATE_ESTABLISHED, // Various active states
        7 => {
            // TCP_CLOSE
            increment_stat(STAT_CONNECTIONS_CLOSED);
            CONN_STATE_CLOSED
        }
        8..=10 => CONN_STATE_CLOSING, // CLOSE_WAIT, LAST_ACK, CLOSING
        _ => CONN_STATE_CONNECTING,
    };

    unsafe {
        // Check if we already have state for this connection
        if let Some(existing_state) = CONNECTION_STATES.get(&key) {
            // Update existing state
            let mut updated_state = *existing_state;
            updated_state.state = conn_state;

            if conn_state == CONN_STATE_CLOSED {
                updated_state.close_time_ns = timestamp;
            }

            let _ = CONNECTION_STATES.insert(&key, &updated_state, 0);
        } else {
            // Create new state entry
            let new_conn_state = ConnectionState {
                key,
                start_time_ns: timestamp,
                close_time_ns: if conn_state == CONN_STATE_CLOSED { timestamp } else { 0 },
                state: conn_state,
                bytes_sent: 0,
                bytes_received: 0,
                pid,
                _padding: [0; 4],
            };
            let _ = CONNECTION_STATES.insert(&key, &new_conn_state, 0);
        }
    }

    Ok(0)
}

/// Track outgoing TCP connections
///
/// Attached to: tcp_v4_connect
///
/// Captures when a new outgoing TCP connection is initiated.
#[kprobe]
pub fn tcp_v4_connect(ctx: ProbeContext) -> u32 {
    match try_tcp_v4_connect(&ctx) {
        Ok(ret) => ret,
        Err(_) => 1,
    }
}

fn try_tcp_v4_connect(ctx: &ProbeContext) -> Result<u32, i64> {
    increment_stat(STAT_TOTAL_EVENTS);
    increment_stat(STAT_CONNECTIONS_OPENED);

    let sock = get_sock_from_context(ctx)?;

    if !is_valid_socket(sock) {
        return Ok(0);
    }

    let key = match extract_connection_key(sock) {
        Ok(k) => k,
        Err(_) => return Ok(0),
    };

    let timestamp = get_timestamp();
    let pid = get_pid();

    unsafe {
        // Create new connection state
        let conn_state = ConnectionState {
            key,
            start_time_ns: timestamp,
            close_time_ns: 0,
            state: CONN_STATE_CONNECTING,
            bytes_sent: 0,
            bytes_received: 0,
            pid,
            _padding: [0; 4],
        };
        let _ = CONNECTION_STATES.insert(&key, &conn_state, 0);
    }

    Ok(0)
}

/// Track connection close
///
/// Attached to: tcp_close
///
/// Captures when a TCP connection is being closed.
#[kprobe]
pub fn tcp_close(ctx: ProbeContext) -> u32 {
    match try_tcp_close(&ctx) {
        Ok(ret) => ret,
        Err(_) => 1,
    }
}

fn try_tcp_close(ctx: &ProbeContext) -> Result<u32, i64> {
    increment_stat(STAT_TOTAL_EVENTS);
    increment_stat(STAT_CONNECTIONS_CLOSED);

    let sock = get_sock_from_context(ctx)?;

    if !is_valid_socket(sock) {
        return Ok(0);
    }

    let key = match extract_connection_key(sock) {
        Ok(k) => k,
        Err(_) => return Ok(0),
    };

    let timestamp = get_timestamp();

    unsafe {
        if let Some(existing_state) = CONNECTION_STATES.get(&key) {
            let mut updated_state = *existing_state;
            updated_state.state = CONN_STATE_CLOSING;
            updated_state.close_time_ns = timestamp;
            let _ = CONNECTION_STATES.insert(&key, &updated_state, 0);
        }
    }

    Ok(0)
}

// ============================================================================
// XDP Packet Processing
// ============================================================================

/// XDP program for early packet processing and monitoring
///
/// Attached to: Network interface (via XDP hook)
///
/// This XDP program runs at the NIC driver level before the network stack,
/// providing ultra-low-latency packet processing and monitoring.
///
/// Key capabilities:
/// - Track packet statistics at XDP level
/// - Monitor packet drops before stack processing
/// - Collect early network metrics
/// - Optionally drop/redirect packets for DDoS mitigation
#[xdp]
pub fn xdp_packet_monitor(ctx: XdpContext) -> u32 {
    match try_xdp_packet_monitor(&ctx) {
        Ok(action) => action,
        Err(_) => xdp_action::XDP_ABORTED,
    }
}

fn try_xdp_packet_monitor(ctx: &XdpContext) -> Result<u32, ()> {
    increment_stat(STAT_TOTAL_EVENTS);
    increment_stat(STAT_XDP_PACKETS);

    // Parse Ethernet header
    let eth_hdr = ptr_at::<EthHdr>(&ctx, 0)?;

    // Check if it's an IP packet (0x0800 = IPv4)
    let eth_proto = u16::from_be(unsafe { (*eth_hdr).ether_type });

    if eth_proto != ETH_P_IP {
        // Not IPv4, pass through
        return Ok(xdp_action::XDP_PASS);
    }

    increment_stat(STAT_XDP_IPV4_PACKETS);

    // Parse IP header
    let ip_hdr = ptr_at::<IpHdr>(&ctx, EthHdr::LEN)?;
    let protocol = unsafe { (*ip_hdr).protocol };

    // Track protocol statistics
    match protocol {
        IPPROTO_TCP => {
            increment_stat(STAT_XDP_TCP_PACKETS);

            // Parse TCP header for additional monitoring
            let tcp_hdr = ptr_at::<TcpHdr>(&ctx, EthHdr::LEN + IpHdr::LEN)?;

            // Extract connection info
            let saddr = u32::from_be(unsafe { (*ip_hdr).saddr });
            let daddr = u32::from_be(unsafe { (*ip_hdr).daddr });
            let sport = u16::from_be(unsafe { (*tcp_hdr).source });
            let dport = u16::from_be(unsafe { (*tcp_hdr).dest });

            // Create connection key
            let key = ConnectionKey {
                saddr,
                daddr,
                sport,
                dport,
            };

            // Update XDP packet counters for this connection
            unsafe {
                if let Some(stats) = XDP_CONN_STATS.get_ptr_mut(&key) {
                    (*stats).packet_count += 1;
                    (*stats).byte_count += (ctx.data_end() - ctx.data()) as u64;
                    (*stats).last_seen_ns = get_timestamp();
                } else {
                    // Create new stats entry
                    let new_stats = XdpConnStats {
                        packet_count: 1,
                        byte_count: (ctx.data_end() - ctx.data()) as u64,
                        last_seen_ns: get_timestamp(),
                        drop_count: 0,
                    };
                    let _ = XDP_CONN_STATS.insert(&key, &new_stats, 0);
                }
            }
        }
        IPPROTO_UDP => {
            increment_stat(STAT_XDP_UDP_PACKETS);
        }
        IPPROTO_ICMP => {
            increment_stat(STAT_XDP_ICMP_PACKETS);
        }
        _ => {
            increment_stat(STAT_XDP_OTHER_PACKETS);
        }
    }

    // Pass all packets to network stack for normal processing
    // In a production scenario, you might:
    // - Return XDP_DROP to drop malicious packets
    // - Return XDP_TX to reflect packets back
    // - Return XDP_REDIRECT to redirect to another interface
    Ok(xdp_action::XDP_PASS)
}

// Helper function to safely access packet data
#[inline(always)]
fn ptr_at<T>(ctx: &XdpContext, offset: usize) -> Result<*const T, ()> {
    let start = ctx.data();
    let end = ctx.data_end();
    let len = core::mem::size_of::<T>();

    if start + offset + len > end {
        return Err(());
    }

    Ok((start + offset) as *const T)
}

// Simplified packet header structures
#[repr(C)]
struct EthHdr {
    dst_addr: [u8; 6],
    src_addr: [u8; 6],
    ether_type: u16,
}

impl EthHdr {
    const LEN: usize = 14;
}

#[repr(C)]
struct IpHdr {
    _bitfield: u8,
    _tos: u8,
    _tot_len: u16,
    _id: u16,
    _frag_off: u16,
    _ttl: u8,
    protocol: u8,
    _check: u16,
    saddr: u32,
    daddr: u32,
}

impl IpHdr {
    const LEN: usize = 20;
}

#[repr(C)]
struct TcpHdr {
    source: u16,
    dest: u16,
    _seq: u32,
    _ack_seq: u32,
    _res1_doff: u16,
    _flags: u16,
    _window: u16,
    _check: u16,
    _urg_ptr: u16,
}

// Ethernet protocol constant
const ETH_P_IP: u16 = 0x0800;
