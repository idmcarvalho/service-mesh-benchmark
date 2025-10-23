FROM python:3.11-slim

# Security: Run as non-root user
RUN groupadd -r mluser -g 1000 && \
    useradd -r -u 1000 -g mluser mluser

# Set working directory
WORKDIR /app

# Copy requirements first for better caching
COPY requirements.txt /app/

# Install dependencies with pinned versions
RUN pip install --no-cache-dir --upgrade pip==24.0 && \
    pip install --no-cache-dir -r /app/requirements.txt

# Copy application code
COPY app.py /app/

# Change ownership to non-root user
RUN chown -R mluser:mluser /app

# Switch to non-root user
USER 1000:1000

# Run the application
CMD ["python", "app.py"]
