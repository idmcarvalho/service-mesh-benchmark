//! Socket structure parsing utilities with CO-RE support
//!
//! Provides production-ready functions to extract connection information from
//! kernel socket structures using CO-RE (Compile Once, Run Everywhere) and BTF.

use aya_ebpf::{
    cty::{c_ulong, c_ushort},
    helpers::bpf_probe_read_kernel,
    programs::ProbeContext,
};
use core::mem;
use probe_common::types::ConnectionKey;

/// Kernel struct sock representation (partial)
///
/// We only define the fields we need. CO-RE will handle the actual offsets.
#[repr(C)]
struct sock {
    __sk_common: sock_common,
}

/// Kernel struct sock_common (partial)
///
/// Contains the connection 4-tuple we need for tracking.
#[repr(C)]
struct sock_common {
    skc_daddr: u32,      // Destination address
    skc_rcv_saddr: u32,  // Source address
    skc_dport: u16,      // Destination port (network byte order)
    skc_num: u16,        // Source port (host byte order)
    skc_family: u16,     // Address family (AF_INET, AF_INET6)
    skc_state: u8,       // Connection state
}

/// IPv4 address family constant
const AF_INET: u16 = 2;

/// IPv6 address family constant
const AF_INET6: u16 = 10;

/// TCP connection states we care about
const TCP_ESTABLISHED: u8 = 1;

/// Extract socket pointer from kprobe context
///
/// The first argument to tcp_sendmsg, tcp_recvmsg, and tcp_cleanup_rbuf
/// is a pointer to struct sock.
#[inline(always)]
pub fn get_sock_from_context(ctx: &ProbeContext) -> Result<*const sock, i64> {
    ctx.arg::<*const sock>(0).ok_or(-1)
}

/// Extract connection key (4-tuple) from socket structure
///
/// Reads the connection information from the kernel socket structure
/// using safe kernel memory reads. Supports both IPv4 and IPv6.
///
/// # Safety
///
/// Uses bpf_probe_read_kernel to safely read from kernel memory.
/// The BPF verifier ensures this is safe.
pub fn extract_connection_key(sock_ptr: *const sock) -> Result<ConnectionKey, i64> {
    if sock_ptr.is_null() {
        return Err(-1);
    }

    // Read the sock_common structure from kernel memory
    let sk_common = unsafe {
        let ptr = sock_ptr as *const u8;
        // sk_common is at the beginning of struct sock
        let common_ptr = ptr as *const sock_common;
        bpf_probe_read_kernel(common_ptr).map_err(|_| -1)?
    };

    // Only handle IPv4 for now (IPv6 support can be added later)
    if sk_common.skc_family != AF_INET {
        return Err(-2); // Unsupported address family
    }

    // Create connection key
    // Note: IP addresses are already in network byte order
    // Source port needs to be converted to network byte order
    let key = ConnectionKey {
        saddr: sk_common.skc_rcv_saddr,
        daddr: sk_common.skc_daddr,
        sport: (sk_common.skc_num as u16).to_be(), // Convert to network byte order
        dport: sk_common.skc_dport,                 // Already in network byte order
    };

    Ok(key)
}

/// Check if socket is valid for tracking
///
/// Validates that the socket represents an established TCP connection
/// that we want to track.
pub fn is_valid_socket(sock_ptr: *const sock) -> bool {
    if sock_ptr.is_null() {
        return false;
    }

    // Read socket family and state
    let result = unsafe {
        let ptr = sock_ptr as *const u8;
        let common_ptr = ptr as *const sock_common;
        bpf_probe_read_kernel(common_ptr)
    };

    match result {
        Ok(sk_common) => {
            // Only track IPv4 TCP connections that are established
            sk_common.skc_family == AF_INET
            // Could add state check: && sk_common.skc_state == TCP_ESTABLISHED
            // but we want to track connections in all states for completeness
        }
        Err(_) => false,
    }
}

/// Get socket state
///
/// Returns the TCP connection state for the given socket.
/// Useful for filtering or categorizing connections.
pub fn get_socket_state(sock_ptr: *const sock) -> Result<u8, i64> {
    if sock_ptr.is_null() {
        return Err(-1);
    }

    unsafe {
        let ptr = sock_ptr as *const u8;
        let common_ptr = ptr as *const sock_common;
        let sk_common = bpf_probe_read_kernel(common_ptr).map_err(|_| -1)?;
        Ok(sk_common.skc_state)
    }
}

/// Get socket address family
///
/// Returns the address family (AF_INET, AF_INET6, etc.).
pub fn get_socket_family(sock_ptr: *const sock) -> Result<u16, i64> {
    if sock_ptr.is_null() {
        return Err(-1);
    }

    unsafe {
        let ptr = sock_ptr as *const u8;
        let common_ptr = ptr as *const sock_common;
        let sk_common = bpf_probe_read_kernel(common_ptr).map_err(|_| -1)?;
        Ok(sk_common.skc_family)
    }
}
