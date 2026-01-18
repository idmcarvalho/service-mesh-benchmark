//! eBPF program loader
//!
//! Handles loading the eBPF program and attaching kprobes, tracepoints, and XDP programs.

use anyhow::{Context, Result};
use aya::{
    maps::perf::AsyncPerfEventArray,
    programs::{KProbe, TracePoint, Xdp, XdpFlags},
    Bpf,
};
use log::{info, warn};
use std::path::PathBuf;

/// Result of attaching an optional eBPF program
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AttachResult {
    /// Program successfully attached
    Attached,
    /// Program not found in eBPF object (optional feature)
    NotFound,
}

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
    /// - tcp_drop
    /// - tcp_set_state
    /// - tcp_v4_connect
    /// - tcp_close
    ///
    /// # Returns
    ///
    /// Result indicating success or failure
    pub fn attach_kprobes(&mut self) -> Result<()> {
        info!("Attaching kprobes for latency tracking...");

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

        info!("Attaching kprobes for packet drop tracking...");

        // Attach tcp_drop (may not exist on all kernels, so warn instead of error)
        match self.ebpf.program_mut("tcp_drop") {
            Some(prog) => {
                let program: &mut KProbe = prog
                    .try_into()
                    .context("Failed to get tcp_drop as KProbe")?;
                program.load().context("Failed to load tcp_drop")?;
                match program.attach("tcp_drop", 0) {
                    Ok(_) => info!("  ✓ Attached to tcp_drop"),
                    Err(e) => warn!("  ⚠ Failed to attach tcp_drop (not available on this kernel): {}", e),
                }
            }
            None => warn!("  ⚠ tcp_drop program not found (optional)"),
        }

        info!("Attaching kprobes for connection state tracking...");

        // Attach tcp_set_state
        let program: &mut KProbe = self
            .ebpf
            .program_mut("tcp_set_state")
            .context("tcp_set_state program not found in eBPF object")?
            .try_into()
            .context("Failed to get tcp_set_state as KProbe")?;
        program.load().context("Failed to load tcp_set_state")?;
        program
            .attach("tcp_set_state", 0)
            .context("Failed to attach tcp_set_state kprobe")?;
        info!("  ✓ Attached to tcp_set_state");

        // Attach tcp_v4_connect
        let program: &mut KProbe = self
            .ebpf
            .program_mut("tcp_v4_connect")
            .context("tcp_v4_connect program not found in eBPF object")?
            .try_into()
            .context("Failed to get tcp_v4_connect as KProbe")?;
        program.load().context("Failed to load tcp_v4_connect")?;
        program
            .attach("tcp_v4_connect", 0)
            .context("Failed to attach tcp_v4_connect kprobe")?;
        info!("  ✓ Attached to tcp_v4_connect");

        // Attach tcp_close
        let program: &mut KProbe = self
            .ebpf
            .program_mut("tcp_close")
            .context("tcp_close program not found in eBPF object")?
            .try_into()
            .context("Failed to get tcp_close as KProbe")?;
        program.load().context("Failed to load tcp_close")?;
        program
            .attach("tcp_close", 0)
            .context("Failed to attach tcp_close kprobe")?;
        info!("  ✓ Attached to tcp_close");

        info!("All kprobes attached successfully");

        Ok(())
    }

    /// Attach tracepoints for packet drop tracking
    ///
    /// Attaches to:
    /// - skb:kfree_skb
    ///
    /// # Returns
    ///
    /// Result indicating success or failure
    pub fn attach_tracepoints(&mut self) -> Result<()> {
        info!("Attaching tracepoints...");

        // Attach kfree_skb tracepoint (may not exist on all kernels)
        match self.ebpf.program_mut("kfree_skb_tracepoint") {
            Some(prog) => {
                let program: &mut TracePoint = prog
                    .try_into()
                    .context("Failed to get kfree_skb_tracepoint as TracePoint")?;
                program.load().context("Failed to load kfree_skb_tracepoint")?;
                match program.attach("skb", "kfree_skb") {
                    Ok(_) => info!("  ✓ Attached to skb:kfree_skb tracepoint"),
                    Err(e) => warn!("  ⚠ Failed to attach skb:kfree_skb tracepoint (not available on this kernel): {}", e),
                }
            }
            None => warn!("  ⚠ kfree_skb_tracepoint program not found (optional)"),
        }

        Ok(())
    }

    /// Attach XDP program to network interface
    ///
    /// XDP is optional. Returns NotFound if not in eBPF object, Err on attach failure.
    pub fn attach_xdp(&mut self, interface: &str, mode: XdpFlags) -> Result<AttachResult> {
        info!("Attaching XDP program...");

        match self.ebpf.program_mut("xdp_packet_monitor") {
            Some(prog) => {
                let program: &mut Xdp = prog
                    .try_into()
                    .context("Failed to get xdp_packet_monitor as XDP")?;
                program.load().context("Failed to load xdp_packet_monitor")?;
                program.attach(interface, mode)
                    .with_context(|| format!("Failed to attach XDP to interface '{}' - check permissions and interface exists", interface))?;
                info!("  ✓ Attached XDP to {}", interface);
                Ok(AttachResult::Attached)
            }
            None => {
                warn!("  ⚠ xdp_packet_monitor program not found (optional)");
                Ok(AttachResult::NotFound)
            }
        }
    }

    /// Get the perf event array for reading latency events
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

    /// Get the perf event array for reading packet drop events
    ///
    /// # Returns
    ///
    /// AsyncPerfEventArray for reading packet drop events from the kernel
    pub fn get_packet_drops_array(&mut self) -> Result<AsyncPerfEventArray<aya::maps::MapData>> {
        let map = self
            .ebpf
            .take_map("PACKET_DROPS")
            .context("PACKET_DROPS map not found in eBPF object")?;

        AsyncPerfEventArray::try_from(map)
            .context("Failed to create AsyncPerfEventArray from PACKET_DROPS map")
    }

    /// Get reference to the eBPF object
    ///
    /// Useful for accessing maps or programs directly.
    pub fn ebpf(&mut self) -> &mut Bpf {
        &mut self.ebpf
    }
}
