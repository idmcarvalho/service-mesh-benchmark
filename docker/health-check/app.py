#!/usr/bin/env python3
"""Health Check Service for Service Mesh Benchmarking"""

from flask import Flask, jsonify
import os
import psutil
import time

app = Flask(__name__)
start_time = time.time()

@app.route('/health')
def health():
    return jsonify({
        'status': 'healthy',
        'timestamp': time.time()
    }), 200

@app.route('/ready')
def ready():
    return jsonify({
        'status': 'ready',
        'uptime': time.time() - start_time
    }), 200

@app.route('/metrics')
def metrics():
    return jsonify({
        'cpu_percent': psutil.cpu_percent(interval=0.1),
        'memory_percent': psutil.virtual_memory().percent,
        'disk_percent': psutil.disk_usage('/').percent,
        'uptime_seconds': time.time() - start_time
    }), 200

@app.route('/probe')
def probe():
    """Comprehensive health probe"""
    try:
        cpu = psutil.cpu_percent(interval=0.1)
        mem = psutil.virtual_memory()

        status = 'healthy'
        if cpu > 90 or mem.percent > 90:
            status = 'degraded'

        return jsonify({
            'status': status,
            'cpu_percent': cpu,
            'memory_mb': mem.used / 1024 / 1024,
            'memory_percent': mem.percent,
            'uptime': time.time() - start_time,
            'pid': os.getpid()
        }), 200
    except Exception as e:
        return jsonify({
            'status': 'unhealthy',
            'error': str(e)
        }), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
