FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Install kubectl for Kubernetes interaction
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

# Copy requirements first for better caching
COPY api/requirements.txt /app/api/requirements.txt
RUN pip install --no-cache-dir --upgrade pip==24.0 && \
    pip install --no-cache-dir -r /app/api/requirements.txt

# Copy application code
COPY api/ /app/api/
COPY benchmarks/ /app/benchmarks/
COPY pyproject.toml /app/

# Create non-root user
RUN useradd -m -u 1000 -s /bin/bash benchmark && \
    chown -R benchmark:benchmark /app

# Switch to non-root user
USER benchmark

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Run the application
CMD ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000"]
