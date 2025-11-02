//! eBPF program loader
//!
//! Handles loading the eBPF program and attaching kprobes.

use anyhow::{Context, Result};
use aya::{
    maps::perf::AsyncPerfEventArray,
    programs::KProbe,
    Bpf,
};
use log::{info, warn};
use std::path::PathBuf;

use crate::types::LatencyEvent;

/// eBPF program loader and manager
pub struct ProbeLoader {
    ebpf: Bpf,
}

impl ProbeLoader {
    /// Load eBPF program from file or embedded bytecode
    ///
    /// # Arguments
    ///
    /// * `path` - Optional path to eBPF object file. If None, uses embedded bytecode.
    ///
    /// # Returns
    ///
    /// ProbeLoader instance with loaded eBPF program
    pub fn load(path: Option<PathBuf>) -> Result<Self> {
        info!("Loading eBPF program...");

        let ebpf = if let Some(obj_path) = path {
            info!("Loading eBPF object from: {:?}", obj_path);
            let data = std::fs::read(&obj_path)
                .with_context(|| format!("Failed to read eBPF object file: {:?}", obj_path))?;
            Bpf::load(&data).context("Failed to load eBPF program")?
        } else {
            // Try to load embedded bytecode
            #[cfg(feature = "embedded")]
            {
                info!("Loading embedded eBPF program...");
                let data = include_bytes!(concat!(
                    env!("CARGO_MANIFEST_DIR"),
                    "/../../target/bpfel-unknown-none/release/latency-probe"
                ));
                Bpf::load(data).context("Failed to load embedded eBPF program")?
            }
            #[cfg(not(feature = "embedded"))]
            {
                anyhow::bail!(
                    "No eBPF object file provided. Use --ebpf-object or compile with 'embedded' feature"
                );
            }
        };

        info!("eBPF program loaded successfully");

        Ok(Self { ebpf })
    }

    /// Initialize eBPF logger
    ///
    /// Enables kernel-side logging from the eBPF program.
    /// Non-fatal if it fails.
    pub fn init_logger(&mut self) {
        // eBPF logger temporarily disabled due to version mismatch
        // TODO: Update to compatible aya-log version when available
        warn!("eBPF logger not available in aya 0.12 - logging from eBPF program will not be captured");
    }

    /// Attach kprobes to kernel functions
    ///
    /// Attaches to:
    /// - tcp_sendmsg
    /// - tcp_recvmsg
    /// - tcp_cleanup_rbuf
    ///
    /// # Returns
    ///
    /// Result indicating success or failure
    pub fn attach_kprobes(&mut self) -> Result<()> {
        info!("Attaching kprobes...");

        // Attach tcp_sendmsg
        let program: &mut KProbe = self
            .ebpf
            .program_mut("tcp_sendmsg")
            .context("tcp_sendmsg program not found in eBPF object")?
            .try_into()
            .context("Failed to get tcp_sendmsg as KProbe")?;
        program.load().context("Failed to load tcp_sendmsg")?;
        program
            .attach("tcp_sendmsg", 0)
            .context("Failed to attach tcp_sendmsg kprobe")?;
        info!("  ✓ Attached to tcp_sendmsg");

        // Attach tcp_recvmsg
        let program: &mut KProbe = self
            .ebpf
            .program_mut("tcp_recvmsg")
            .context("tcp_recvmsg program not found in eBPF object")?
            .try_into()
            .context("Failed to get tcp_recvmsg as KProbe")?;
        program.load().context("Failed to load tcp_recvmsg")?;
        program
            .attach("tcp_recvmsg", 0)
            .context("Failed to attach tcp_recvmsg kprobe")?;
        info!("  ✓ Attached to tcp_recvmsg");

        // Attach tcp_cleanup_rbuf
        let program: &mut KProbe = self
            .ebpf
            .program_mut("tcp_cleanup_rbuf")
            .context("tcp_cleanup_rbuf program not found in eBPF object")?
            .try_into()
            .context("Failed to get tcp_cleanup_rbuf as KProbe")?;
        program.load().context("Failed to load tcp_cleanup_rbuf")?;
        program
            .attach("tcp_cleanup_rbuf", 0)
            .context("Failed to attach tcp_cleanup_rbuf kprobe")?;
        info!("  ✓ Attached to tcp_cleanup_rbuf");

        info!("All kprobes attached successfully");

        Ok(())
    }

    /// Get the perf event array for reading events
    ///
    /// # Returns
    ///
    /// AsyncPerfEventArray for reading latency events from the kernel
    pub fn get_perf_array(&mut self) -> Result<AsyncPerfEventArray<aya::maps::MapData>> {
        let map = self
            .ebpf
            .take_map("EVENTS")
            .context("EVENTS map not found in eBPF object")?;

        AsyncPerfEventArray::try_from(map)
            .context("Failed to create AsyncPerfEventArray from EVENTS map")
    }

    /// Get reference to the eBPF object
    ///
    /// Useful for accessing maps or programs directly.
    pub fn ebpf(&mut self) -> &mut Bpf {
        &mut self.ebpf
    }
}
