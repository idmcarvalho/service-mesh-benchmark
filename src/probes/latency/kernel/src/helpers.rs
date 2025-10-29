//! Helper functions for eBPF programs
//!
//! Provides safe wrappers around BPF helper functions and
//! utility functions for common operations.

use aya_ebpf::helpers::{bpf_get_current_pid_tgid, bpf_ktime_get_ns};
use probe_common::{types::*, constants::*};

/// Get current timestamp in nanoseconds
#[inline(always)]
pub fn get_timestamp() -> u64 {
    unsafe { bpf_ktime_get_ns() }
}

/// Get current process ID
#[inline(always)]
pub fn get_pid() -> u32 {
    let pid_tgid = unsafe { bpf_get_current_pid_tgid() };
    (pid_tgid >> 32) as u32
}

/// Get current thread ID
#[inline(always)]
pub fn get_tid() -> u32 {
    let pid_tgid = unsafe { bpf_get_current_pid_tgid() };
    (pid_tgid & 0xFFFFFFFF) as u32
}

/// Validate latency measurement
///
/// Returns true if the latency is within valid bounds.
/// Filters out obvious measurement errors.
#[inline(always)]
pub fn is_valid_latency(latency_ns: u64) -> bool {
    latency_ns >= MIN_LATENCY_NS && latency_ns <= MAX_LATENCY_NS
}

/// Increment a statistics counter
///
/// Safely increments a counter in the STATS map.
#[inline(always)]
pub fn increment_stat(stat_id: u32) {
    use crate::maps::STATS;

    unsafe {
        if let Some(count) = STATS.get(&stat_id) {
            let new_count = *count + 1;
            let _ = STATS.insert(&stat_id, &new_count, 0);
        } else {
            let _ = STATS.insert(&stat_id, &1u64, 0);
        }
    }
}

/// Create a latency event
///
/// Constructs a properly formatted LatencyEvent for sending to userspace.
#[inline(always)]
pub fn create_latency_event(
    key: ConnectionKey,
    timestamp_ns: u64,
    latency_ns: u64,
    event_type: u8,
) -> LatencyEvent {
    LatencyEvent {
        key,
        timestamp_ns,
        latency_ns,
        pid: get_pid(),
        event_type,
        _padding: [0; 3],
    }
}
