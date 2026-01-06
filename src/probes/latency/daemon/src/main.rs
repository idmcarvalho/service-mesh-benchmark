//! eBPF Latency Probe - Userspace Program
//!
//! Loads the eBPF latency tracking program, attaches kprobes,
//! collects events, and exports metrics.
//!
//! ## Usage
//!
//! ```bash
//! # Run for 60 seconds and export to JSON
//! sudo ./latency-probe --duration 60 --output metrics.json
//!
//! # Run with sampling (capture 1 in 100 events)
//! sudo ./latency-probe --duration 60 --sample-rate 100
//!
//! # Use external eBPF object file
//! sudo ./latency-probe --ebpf-object path/to/latency-probe.o
//!
//! # Export to Prometheus format
//! sudo ./latency-probe --duration 60 --format prometheus --output metrics.prom
//! ```

use anyhow::Result;
use clap::Parser;
use latency_probe_userspace::{
    collector::MetricsCollector,
    events::EventProcessor,
    exporter::{ExporterType, InfluxExporter, JsonExporter, MetricsExporter, PrometheusExporter},
    loader::ProbeLoader,
    types::LatencyMetrics,
};
use log::info;
use std::{path::PathBuf, sync::Arc, time::Duration};
use tokio::{
    signal,
    sync::Mutex,
    time::{sleep, Instant},
};

/// Network latency tracking probe using eBPF
#[derive(Parser, Debug)]
#[clap(author, version, about, long_about = None)]
struct Args {
    /// Duration to run the probe (in seconds, 0 = infinite)
    #[clap(short, long, default_value_t = 60)]
    duration: u64,

    /// Output file for metrics
    #[clap(short, long, default_value = "latency-metrics.json")]
    output: PathBuf,

    /// Output format (json, prometheus, influx)
    #[clap(short, long, default_value = "json")]
    format: String,

    /// Sampling rate (1 = capture all, 100 = capture 1 in 100)
    #[clap(short, long, default_value_t = 1)]
    sample_rate: u32,

    /// Filter by specific service (format: IP:PORT) - NOT YET IMPLEMENTED
    #[clap(long)]
    filter_service: Option<String>,

    /// Verbose logging
    #[clap(short, long)]
    verbose: bool,

    /// Path to eBPF object file (if not embedded)
    #[clap(long)]
    ebpf_object: Option<PathBuf>,

    /// Progress reporting interval in seconds
    #[clap(long, default_value_t = 10)]
    progress_interval: u64,
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();

    // Initialize logging
    env_logger::Builder::from_default_env()
        .filter_level(if args.verbose {
            log::LevelFilter::Debug
        } else {
            log::LevelFilter::Info
        })
        .init();

    print_banner();

    info!("Starting eBPF latency probe...");
    info!(
        "   Duration: {} seconds",
        if args.duration == 0 {
            "infinite".to_string()
        } else {
            args.duration.to_string()
        }
    );
    info!("   Output: {:?}", args.output);
    info!("   Format: {}", args.format);
    info!("   Sample rate: 1 in {}", args.sample_rate);

    // Validate sample rate
    if args.sample_rate == 0 {
        anyhow::bail!("Sample rate must be >= 1");
    }

    // Parse export format
    let export_format = match args.format.to_lowercase().as_str() {
        "json" => ExporterType::Json,
        "prometheus" | "prom" => ExporterType::Prometheus,
        "influx" | "influxdb" => ExporterType::Influx,
        _ => anyhow::bail!(
            "Unsupported format: {}. Use json, prometheus, or influx",
            args.format
        ),
    };

    // Load eBPF program
    let mut loader = ProbeLoader::load(args.ebpf_object.clone())?;

    // Initialize eBPF logger (optional)
    loader.init_logger();

    // Attach kprobes
    loader.attach_kprobes()?;

    // Attach tracepoints
    loader.attach_tracepoints()?;

    // Get perf event array
    let perf_array = loader.get_perf_array()?;

    info!("Collecting metrics...");

    // Create metrics collector
    let collector = Arc::new(Mutex::new(MetricsCollector::new()));

    // Create event processor
    let processor = EventProcessor::new(Arc::clone(&collector), args.sample_rate, args.verbose);

    // Spawn per-CPU event readers
    processor.spawn_cpu_readers(perf_array).await?;

    // Spawn progress reporter
    processor.spawn_progress_reporter(args.progress_interval);

    // Run for specified duration or until interrupted
    let start_time = Instant::now();
    let duration = if args.duration > 0 {
        Some(Duration::from_secs(args.duration))
    } else {
        None
    };

    if let Some(d) = duration {
        tokio::select! {
            _ = sleep(d) => {
                info!("Duration reached, shutting down...");
            }
            _ = signal::ctrl_c() => {
                info!("Interrupted, shutting down...");
            }
        }
    } else {
        signal::ctrl_c().await?;
        info!("Interrupted, shutting down...");
    }

    let elapsed = start_time.elapsed().as_secs();

    info!("Generating metrics report...");

    // Generate final metrics
    let collector = collector.lock().await;
    let metrics = collector.generate_metrics(elapsed);

    // Export metrics based on format
    match export_format {
        ExporterType::Json => {
            let exporter = JsonExporter::new(args.output.clone(), true);
            exporter.export(&metrics)?;
        }
        ExporterType::Prometheus => {
            let exporter = PrometheusExporter::new(args.output.clone());
            exporter.export(&metrics)?;
        }
        ExporterType::Influx => {
            let exporter = InfluxExporter::new(args.output.clone(), "latency_probe".to_string());
            exporter.export(&metrics)?;
        }
    }

    info!("Metrics written to {:?}", args.output);

    // Print summary
    print_summary(&metrics);

    Ok(())
}

fn print_banner() {
    println!(
        r#"
╔═══════════════════════════════════════════════════╗
║       eBPF Latency Probe - Service Mesh           ║
║            Benchmark Framework                    ║
╚═══════════════════════════════════════════════════╝
    "#
    );
}

fn print_summary(metrics: &LatencyMetrics) {
    info!("");
    info!("============================================");
    info!("             Summary Report");
    info!("============================================");
    info!("");
    info!("  Total events:       {}", metrics.total_events);
    info!("  Unique connections: {}", metrics.connections.len());
    info!("  Duration:           {} seconds", metrics.duration_seconds);
    info!("");
    info!("  Latency Percentiles (μs):");
    info!("    p50:  {:>10.2}", metrics.percentiles.p50);
    info!("    p75:  {:>10.2}", metrics.percentiles.p75);
    info!("    p90:  {:>10.2}", metrics.percentiles.p90);
    info!("    p95:  {:>10.2}", metrics.percentiles.p95);
    info!("    p99:  {:>10.2}", metrics.percentiles.p99);
    info!("    p999: {:>10.2}", metrics.percentiles.p999);
    info!("");
    info!("  Histogram:");
    info!("    0-1ms:       {:>8}", metrics.histogram.bucket_0_1ms);
    info!("    1-5ms:       {:>8}", metrics.histogram.bucket_1_5ms);
    info!("    5-10ms:      {:>8}", metrics.histogram.bucket_5_10ms);
    info!("    10-50ms:     {:>8}", metrics.histogram.bucket_10_50ms);
    info!("    50-100ms:    {:>8}", metrics.histogram.bucket_50_100ms);
    info!("    100ms+:      {:>8}", metrics.histogram.bucket_100ms_plus);
    info!("");
    info!("  Event Type Breakdown:");
    info!(
        "    tcp_sendmsg:      {:>8}",
        metrics.event_type_breakdown.tcp_sendmsg
    );
    info!(
        "    tcp_recvmsg:      {:>8}",
        metrics.event_type_breakdown.tcp_recvmsg
    );
    info!(
        "    tcp_cleanup_rbuf: {:>8}",
        metrics.event_type_breakdown.tcp_cleanup_rbuf
    );
    info!("");
    info!("============================================");
}
