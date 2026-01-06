# Multi-stage build for Service Mesh Benchmark API with eBPF support
# Stage 1: Build eBPF probes
FROM rust:1.75-slim as ebpf-builder

# Install eBPF build dependencies
RUN apt-get update && apt-get install -y \
    clang \
    llvm-15 \
    libelf-dev \
    linux-headers-generic \
    pkg-config \
    make \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /build

# Copy eBPF probe source
COPY src/probes/ ./src/probes/

# Install bpf-linker for eBPF compilation
RUN cargo install bpf-linker || echo "bpf-linker installation optional"

# Build eBPF probes
WORKDIR /build/src/probes/latency
RUN if [ -f "Cargo.toml" ]; then \
        rustup target add bpfel-unknown-none; \
        cargo build --release --workspace || echo "eBPF build skipped - will use fallback"; \
    fi

# Stage 2: Build Python dependencies
FROM python:3.11-slim as python-builder

# Install system dependencies for Python packages
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    make \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements file
COPY src/api/requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir --user -r requirements.txt

# Stage 3: Final production image
FROM python:3.11-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libpq5 \
    curl \
    wrk \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Install ghz for gRPC benchmarking (if available)
RUN curl -sL https://github.com/bojand/ghz/releases/download/v0.117.0/ghz-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin ghz || echo "ghz installation skipped"

# Create non-root user for security
RUN groupadd -r benchmark && useradd -r -g benchmark benchmark

# Set working directory
WORKDIR /app

# Copy Python dependencies from builder
COPY --from=python-builder /root/.local /home/benchmark/.local

# Copy application code
COPY src/ ./src/
COPY workloads/ ./workloads/
COPY generate-report.py ./

# Create necessary directories and copy eBPF probe if available
RUN mkdir -p /app/workloads/scripts/results /app/bin && \
    chown -R benchmark:benchmark /app

# Copy eBPF probe binary from builder (if built successfully)
# Using RUN with cp to handle optional file
RUN --mount=type=bind,from=ebpf-builder,source=/build/src/probes/latency/daemon/target/release/latency-probe,target=/tmp/latency-probe \
    cp /tmp/latency-probe /app/bin/latency-probe 2>/dev/null || echo "eBPF probe not built - will use API-only mode"

# Switch to non-root user
USER benchmark

# Add local bin to PATH
ENV PATH=/home/benchmark/.local/bin:/app/bin:$PATH
ENV PYTHONPATH=/app

# Expose API port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Run the application
CMD ["python", "-m", "uvicorn", "src.api.main:app", "--host", "0.0.0.0", "--port", "8000"]
