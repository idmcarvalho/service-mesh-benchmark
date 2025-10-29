//! eBPF Latency Probe - Kernel Space Program
//!
//! This eBPF program tracks TCP network latency at the kernel level
//! by attaching to tcp_sendmsg, tcp_recvmsg, and tcp_cleanup_rbuf.
//!
//! The program measures the time between send and receive operations
//! for each connection and sends the latency data to userspace via
//! a perf event array.
//!
//! ## Architecture
//!
//! ```text
//! tcp_sendmsg() -> Record timestamp in CONNECTION_START map
//!                  |
//!                  v
//! tcp_recvmsg() -> Calculate latency, send event to EVENTS map
//!                  |
//!                  v
//! Userspace    -> Read events, aggregate statistics, export metrics
//! ```
//!
//! ## Usage
//!
//! This program must be compiled for the bpfel-unknown-none target:
//!
//! ```bash
//! cargo build --release --target=bpfel-unknown-none
//! ```
//!
//! The compiled bytecode is then loaded by the userspace program.

#![no_std]
#![no_main]

// Re-export probe handlers for the userspace loader
use aya_ebpf::macros::map;

mod handlers;
mod helpers;
mod maps;
mod socket_parser;

// Re-export kprobe functions so they're visible to the loader
pub use handlers::{tcp_cleanup_rbuf, tcp_recvmsg, tcp_sendmsg};

// Re-export maps for verification
pub use maps::{CONNECTION_START, EVENTS, STATS};

#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    // eBPF programs cannot panic - this should never be reached
    // The verifier should catch any potential panics
    loop {}
}
