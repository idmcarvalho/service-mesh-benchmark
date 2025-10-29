//! Shared types and utilities for eBPF probes
//!
//! This crate provides common data structures, constants, and utilities
//! shared between eBPF kernel programs and userspace loaders.

#![no_std]

pub mod types;
pub mod constants;

// Re-export commonly used types
pub use types::{ConnectionKey, LatencyEvent, PacketDropEvent, ConnectionState};
pub use constants::*;
