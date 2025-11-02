//! Kprobe handlers for TCP latency tracking
//!
//! Implements the actual eBPF programs that attach to kernel functions
//! and measure network latency.

use aya_ebpf::{macros::kprobe, programs::ProbeContext};
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
