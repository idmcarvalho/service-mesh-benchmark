FROM python:3.11-slim

# Security: Run as non-root user
RUN groupadd -r appuser -g 1000 && \
    useradd -r -u 1000 -g appuser appuser

# Set working directory
WORKDIR /app

# Copy requirements first for better caching
COPY requirements.txt /app/

# Install dependencies with pinned versions
RUN pip install --no-cache-dir --upgrade pip==24.0 && \
    pip install --no-cache-dir -r /app/requirements.txt

# Copy application code
COPY app.py /app/

# Create necessary directories with proper permissions
RUN mkdir -p /tmp /app/cache && \
    chown -R appuser:appuser /app /tmp

# Switch to non-root user
USER 1000:1000

# Expose port
EXPOSE 8080

# Run the application
CMD ["python", "app.py"]
