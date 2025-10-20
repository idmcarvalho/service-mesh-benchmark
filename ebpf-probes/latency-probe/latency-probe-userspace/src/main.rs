use anyhow::{Context, Result};
use aya::{
    maps::{perf::AsyncPerfEventArray, HashMap as AyaHashMap},
    programs::KProbe,
    util::online_cpus,
    Ebpf,
};
use aya_log::EbpfLogger;
use bytes::BytesMut;
use clap::Parser;
use log::{debug, info, warn};
use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    fs::File,
    io::Write,
    net::Ipv4Addr,
    path::PathBuf,
    sync::Arc,
    time::Duration,
};
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

    /// Output file for metrics (JSON format)
    #[clap(short, long, default_value = "latency-metrics.json")]
    output: PathBuf,

    /// Sampling rate (1 = capture all, 100 = capture 1 in 100)
    #[clap(short, long, default_value_t = 1)]
    sample_rate: u32,

    /// Filter by specific service (format: IP:PORT)
    #[clap(long)]
    filter_service: Option<String>,

    /// Verbose logging
    #[clap(short, long)]
    verbose: bool,

    /// Path to eBPF object file (if not embedded)
    #[clap(long)]
    ebpf_object: Option<PathBuf>,
}

/// Must match the eBPF program's struct layout
#[repr(C)]
#[derive(Clone, Copy, Debug)]
struct ConnectionKey {
    saddr: u32,
    daddr: u32,
    sport: u16,
    dport: u16,
}

/// Must match the eBPF program's struct layout
#[repr(C)]
#[derive(Clone, Copy, Debug)]
struct LatencyEvent {
    key: ConnectionKey,
    timestamp_ns: u64,
    latency_ns: u64,
    pid: u32,
    event_type: u8,
}

unsafe impl aya::Pod for LatencyEvent {}

#[derive(Serialize, Deserialize, Debug)]
struct LatencyMetrics {
    timestamp: String,
    duration_seconds: u64,
    total_events: u64,
    connections: HashMap<String, ConnectionMetrics>,
    histogram: LatencyHistogram,
    percentiles: Percentiles,
    event_type_breakdown: EventTypeBreakdown,
}

#[derive(Serialize, Deserialize, Debug)]
struct ConnectionMetrics {
    source: String,
    destination: String,
    events: u64,
    min_latency_us: f64,
    max_latency_us: f64,
    avg_latency_us: f64,
    std_dev_us: f64,
}

#[derive(Serialize, Deserialize, Debug, Default)]
struct LatencyHistogram {
    #[serde(rename = "0-1ms")]
    bucket_0_1ms: u64,
    #[serde(rename = "1-5ms")]
    bucket_1_5ms: u64,
    #[serde(rename = "5-10ms")]
    bucket_5_10ms: u64,
    #[serde(rename = "10-50ms")]
    bucket_10_50ms: u64,
    #[serde(rename = "50-100ms")]
    bucket_50_100ms: u64,
    #[serde(rename = "100ms+")]
    bucket_100ms_plus: u64,
}

#[derive(Serialize, Deserialize, Debug, Default)]
struct Percentiles {
    p50: f64,
    p75: f64,
    p90: f64,
    p95: f64,
    p99: f64,
    p999: f64,
}

#[derive(Serialize, Deserialize, Debug, Default)]
struct EventTypeBreakdown {
    tcp_sendmsg: u64,
    tcp_recvmsg: u64,
    tcp_cleanup_rbuf: u64,
}

impl LatencyHistogram {
    fn add_sample(&mut self, latency_us: f64) {
        match latency_us {
            l if l < 1000.0 => self.bucket_0_1ms += 1,
            l if l < 5000.0 => self.bucket_1_5ms += 1,
            l if l < 10000.0 => self.bucket_5_10ms += 1,
            l if l < 50000.0 => self.bucket_10_50ms += 1,
            l if l < 100000.0 => self.bucket_50_100ms += 1,
            _ => self.bucket_100ms_plus += 1,
        }
    }
}

fn connection_key_to_string(key: &ConnectionKey) -> String {
    let saddr = Ipv4Addr::from(u32::from_be(key.saddr));
    let daddr = Ipv4Addr::from(u32::from_be(key.daddr));
    format!(
        "{}:{} -> {}:{}",
        saddr,
        u16::from_be(key.sport),
        daddr,
        u16::from_be(key.dport)
    )
}

fn calculate_percentiles(mut samples: Vec<f64>) -> Percentiles {
    if samples.is_empty() {
        return Percentiles::default();
    }

    samples.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let len = samples.len();

    let percentile = |p: usize| samples[std::cmp::min((len * p / 100).saturating_sub(1), len - 1)];

    Percentiles {
        p50: percentile(50),
        p75: percentile(75),
        p90: percentile(90),
        p95: percentile(95),
        p99: percentile(99),
        p999: percentile(99),
    }
}

fn calculate_std_dev(samples: &[f64], mean: f64) -> f64 {
    if samples.len() <= 1 {
        return 0.0;
    }

    let variance: f64 = samples.iter().map(|x| (x - mean).powi(2)).sum::<f64>() / samples.len() as f64;
    variance.sqrt()
}

/// Aggregated data collection
#[derive(Default)]
struct MetricsCollector {
    all_latencies: Vec<f64>,
    connection_latencies: HashMap<String, Vec<f64>>,
    histogram: LatencyHistogram,
    event_types: EventTypeBreakdown,
    total_events: u64,
}

impl MetricsCollector {
    fn add_event(&mut self, event: &LatencyEvent) {
        let latency_us = event.latency_ns as f64 / 1000.0;

        // Add to global latencies
        self.all_latencies.push(latency_us);

        // Add to per-connection latencies
        let conn_str = connection_key_to_string(&event.key);
        self.connection_latencies
            .entry(conn_str)
            .or_insert_with(Vec::new)
            .push(latency_us);

        // Update histogram
        self.histogram.add_sample(latency_us);

        // Track event types
        match event.event_type {
            0 => self.event_types.tcp_sendmsg += 1,
            1 => self.event_types.tcp_recvmsg += 1,
            2 => self.event_types.tcp_cleanup_rbuf += 1,
            _ => {}
        }

        self.total_events += 1;
    }

    fn generate_metrics(&self, elapsed_secs: u64) -> LatencyMetrics {
        let percentiles = calculate_percentiles(self.all_latencies.clone());

        let connection_metrics: HashMap<String, ConnectionMetrics> = self
            .connection_latencies
            .iter()
            .map(|(key, samples)| {
                let sum: f64 = samples.iter().sum();
                let avg = sum / samples.len() as f64;
                let min = samples.iter().cloned().fold(f64::INFINITY, f64::min);
                let max = samples.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
                let std_dev = calculate_std_dev(samples, avg);

                let parts: Vec<&str> = key.split(" -> ").collect();
                (
                    key.clone(),
                    ConnectionMetrics {
                        source: parts[0].to_string(),
                        destination: parts.get(1).unwrap_or(&"unknown").to_string(),
                        events: samples.len() as u64,
                        min_latency_us: min,
                        max_latency_us: max,
                        avg_latency_us: avg,
                        std_dev_us: std_dev,
                    },
                )
            })
            .collect();

        LatencyMetrics {
            timestamp: chrono::Utc::now().to_rfc3339(),
            duration_seconds: elapsed_secs,
            total_events: self.total_events,
            connections: connection_metrics,
            histogram: self.histogram.clone(),
            percentiles,
            event_type_breakdown: EventTypeBreakdown {
                tcp_sendmsg: self.event_types.tcp_sendmsg,
                tcp_recvmsg: self.event_types.tcp_recvmsg,
                tcp_cleanup_rbuf: self.event_types.tcp_cleanup_rbuf,
            },
        }
    }
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

    info!("🚀 Starting eBPF latency probe...");
    info!("   Duration: {} seconds", if args.duration == 0 { "infinite".to_string() } else { args.duration.to_string() });
    info!("   Output: {:?}", args.output);
    info!("   Sample rate: 1 in {}", args.sample_rate);

    // Load eBPF program
    let mut ebpf = if let Some(path) = &args.ebpf_object {
        info!("📦 Loading eBPF object from: {:?}", path);
        let data = std::fs::read(path)?;
        Ebpf::load(&data)?
    } else {
        // Try to load embedded bytecode
        // This requires compiling the eBPF program first and embedding it
        #[cfg(feature = "embedded")]
        {
            info!("📦 Loading embedded eBPF program...");
            Ebpf::load(include_bytes_aligned!(
                "../../target/bpfel-unknown-none/release/latency-probe"
            ))?
        }
        #[cfg(not(feature = "embedded"))]
        {
            return Err(anyhow::anyhow!(
                "No eBPF object file provided. Use --ebpf-object or compile with 'embedded' feature"
            ));
        }
    };

    // Initialize eBPF logger (optional, for debugging)
    if let Err(e) = EbpfLogger::init(&mut ebpf) {
        warn!("Failed to initialize eBPF logger: {}", e);
    }

    info!("✅ eBPF program loaded successfully");

    // Attach kprobes
    info!("🔗 Attaching kprobes...");

    let program: &mut KProbe = ebpf
        .program_mut("tcp_sendmsg")
        .context("tcp_sendmsg program not found")?
        .try_into()?;
    program.load()?;
    program.attach("tcp_sendmsg", 0)?;
    info!("   ✓ Attached to tcp_sendmsg");

    let program: &mut KProbe = ebpf
        .program_mut("tcp_recvmsg")
        .context("tcp_recvmsg program not found")?
        .try_into()?;
    program.load()?;
    program.attach("tcp_recvmsg", 0)?;
    info!("   ✓ Attached to tcp_recvmsg");

    let program: &mut KProbe = ebpf
        .program_mut("tcp_cleanup_rbuf")
        .context("tcp_cleanup_rbuf program not found")?
        .try_into()?;
    program.load()?;
    program.attach("tcp_cleanup_rbuf", 0)?;
    info!("   ✓ Attached to tcp_cleanup_rbuf");

    info!("✅ All kprobes attached successfully");

    // Set up perf event array to read events
    let mut perf_array = AsyncPerfEventArray::try_from(ebpf.take_map("EVENTS").context("EVENTS map not found")?)?;

    info!("📊 Collecting metrics...");

    // Metrics collector
    let collector = Arc::new(Mutex::new(MetricsCollector::default()));

    // Spawn tasks for each CPU to read events
    let cpus = online_cpus()?;
    for cpu_id in cpus {
        let mut buf = perf_array.open(cpu_id, None)?;
        let collector_clone = Arc::clone(&collector);
        let sample_rate = args.sample_rate;

        tokio::spawn(async move {
            let mut buffers = (0..10)
                .map(|_| BytesMut::with_capacity(std::mem::size_of::<LatencyEvent>()))
                .collect::<Vec<_>>();

            let mut sample_counter = 0u32;

            loop {
                let events = match buf.read_events(&mut buffers).await {
                    Ok(events) => events,
                    Err(e) => {
                        warn!("Error reading events from CPU {}: {}", cpu_id, e);
                        continue;
                    }
                };

                for buf in buffers.iter_mut().take(events.read) {
                    // Apply sampling
                    sample_counter += 1;
                    if sample_counter % sample_rate != 0 {
                        continue;
                    }

                    let ptr = buf.as_ptr() as *const LatencyEvent;
                    let event = unsafe { ptr.read_unaligned() };

                    debug!(
                        "Event: {:?} -> {:?}, latency: {:.2}μs, type: {}",
                        Ipv4Addr::from(u32::from_be(event.key.saddr)),
                        Ipv4Addr::from(u32::from_be(event.key.daddr)),
                        event.latency_ns as f64 / 1000.0,
                        event.event_type
                    );

                    let mut collector = collector_clone.lock().await;
                    collector.add_event(&event);
                }
            }
        });
    }

    info!("✅ Event readers spawned for {} CPUs", cpus.len());

    // Progress reporting
    let collector_clone = Arc::clone(&collector);
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(10));
        loop {
            interval.tick().await;
            let collector = collector_clone.lock().await;
            info!(
                "📈 Progress: {} events collected, {} unique connections",
                collector.total_events,
                collector.connection_latencies.len()
            );
        }
    });

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
                info!("⏱️  Duration reached, shutting down...");
            }
            _ = signal::ctrl_c() => {
                info!("🛑 Interrupted, shutting down...");
            }
        }
    } else {
        signal::ctrl_c().await?;
        info!("🛑 Interrupted, shutting down...");
    }

    let elapsed = start_time.elapsed().as_secs();

    info!("🔄 Generating metrics report...");

    // Generate final metrics
    let collector = collector.lock().await;
    let metrics = collector.generate_metrics(elapsed);

    // Write metrics to file
    let json = serde_json::to_string_pretty(&metrics)?;
    let mut file = File::create(&args.output)?;
    file.write_all(json.as_bytes())?;

    info!("✅ Metrics written to {:?}", args.output);
    info!("");
    info!("📊 Summary:");
    info!("   Total events: {}", metrics.total_events);
    info!("   Unique connections: {}", metrics.connections.len());
    info!("   Duration: {} seconds", elapsed);
    info!("");
    info!("   Latency percentiles (μs):");
    info!("      p50:  {:.2}", metrics.percentiles.p50);
    info!("      p75:  {:.2}", metrics.percentiles.p75);
    info!("      p90:  {:.2}", metrics.percentiles.p90);
    info!("      p95:  {:.2}", metrics.percentiles.p95);
    info!("      p99:  {:.2}", metrics.percentiles.p99);
    info!("      p999: {:.2}", metrics.percentiles.p999);
    info!("");
    info!("   Event type breakdown:");
    info!("      tcp_sendmsg:      {}", metrics.event_type_breakdown.tcp_sendmsg);
    info!("      tcp_recvmsg:      {}", metrics.event_type_breakdown.tcp_recvmsg);
    info!("      tcp_cleanup_rbuf: {}", metrics.event_type_breakdown.tcp_cleanup_rbuf);

    Ok(())
}
