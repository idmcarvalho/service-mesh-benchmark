//! Event processing from eBPF perf buffers
//!
//! Handles reading events from per-CPU perf buffers and processing them asynchronously.

use crate::{collector::MetricsCollector, types::LatencyEvent};
use anyhow::Result;
use aya::{maps::perf::AsyncPerfEventArray, util::online_cpus};
use bytes::BytesMut;
use log::{debug, info, warn};
use std::{sync::Arc, time::Duration};
use tokio::{sync::Mutex, time::interval};

/// Event processor that reads from perf buffers
pub struct EventProcessor {
    collector: Arc<Mutex<MetricsCollector>>,
    sample_rate: u32,
    verbose: bool,
}

impl EventProcessor {
    /// Create a new event processor
    ///
    /// # Arguments
    ///
    /// * `collector` - Shared metrics collector
    /// * `sample_rate` - Sampling rate (1 = all events, N = 1 in N events)
    /// * `verbose` - Enable verbose logging
    pub fn new(collector: Arc<Mutex<MetricsCollector>>, sample_rate: u32, verbose: bool) -> Self {
        Self {
            collector,
            sample_rate,
            verbose,
        }
    }

    /// Spawn per-CPU event readers
    ///
    /// Creates a task for each CPU to read events from its perf buffer.
    ///
    /// # Arguments
    ///
    /// * `perf_array` - Perf event array from the eBPF program
    ///
    /// # Returns
    ///
    /// Result indicating success or failure
    pub async fn spawn_cpu_readers(&self, mut perf_array: AsyncPerfEventArray<'_>) -> Result<()> {
        let cpus = online_cpus()?;
        info!("Spawning event readers for {} CPUs", cpus.len());

        for cpu_id in cpus {
            let mut buf = perf_array.open(cpu_id, None)?;
            let collector_clone = Arc::clone(&self.collector);
            let sample_rate = self.sample_rate;
            let verbose = self.verbose;

            tokio::spawn(async move {
                // Pre-allocate buffers for reading events
                let mut buffers = (0..10)
                    .map(|_| BytesMut::with_capacity(std::mem::size_of::<LatencyEvent>()))
                    .collect::<Vec<_>>();

                let mut sample_counter = 0u32;

                loop {
                    // Read events from the perf buffer
                    let events = match buf.read_events(&mut buffers).await {
                        Ok(events) => events,
                        Err(e) => {
                            warn!("Error reading events from CPU {}: {}", cpu_id, e);
                            continue;
                        }
                    };

                    // Process each event
                    for buf in buffers.iter_mut().take(events.read) {
                        // Apply sampling
                        sample_counter += 1;
                        if sample_counter % sample_rate != 0 {
                            continue;
                        }

                        // Parse event from buffer
                        let ptr = buf.as_ptr() as *const LatencyEvent;
                        let event = unsafe { ptr.read_unaligned() };

                        if verbose {
                            debug!(
                                "Event: {:?} -> {:?}, latency: {:.2}μs, type: {}",
                                std::net::Ipv4Addr::from(u32::from_be(event.key.saddr)),
                                std::net::Ipv4Addr::from(u32::from_be(event.key.daddr)),
                                event.latency_ns as f64 / 1000.0,
                                event.event_type
                            );
                        }

                        // Add to collector
                        let mut collector = collector_clone.lock().await;
                        collector.add_event(&event);
                    }
                }
            });
        }

        Ok(())
    }

    /// Spawn progress reporter
    ///
    /// Creates a task that periodically reports collection progress.
    ///
    /// # Arguments
    ///
    /// * `interval_secs` - Reporting interval in seconds
    pub fn spawn_progress_reporter(&self, interval_secs: u64) {
        let collector_clone = Arc::clone(&self.collector);

        tokio::spawn(async move {
            let mut ticker = interval(Duration::from_secs(interval_secs));

            loop {
                ticker.tick().await;

                let collector = collector_clone.lock().await;
                info!(
                    "📈 Progress: {} events collected, {} unique connections",
                    collector.event_count(),
                    collector.connection_count()
                );
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_event_processor_creation() {
        let collector = Arc::new(Mutex::new(MetricsCollector::new()));
        let processor = EventProcessor::new(collector, 1, false);

        assert_eq!(processor.sample_rate, 1);
        assert_eq!(processor.verbose, false);
    }
}
