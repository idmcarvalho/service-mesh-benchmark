#!/usr/bin/env python3
"""
Service Mesh Benchmark Report Generator
Generates comprehensive reports from benchmark results with detailed metrics and charts
"""

import json
import glob
import os
import re
import statistics
from datetime import datetime
from pathlib import Path
import argparse


def load_json_file(filepath):
    """Load JSON file safely"""
    try:
        with open(filepath, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"Error loading {filepath}: {e}")
        return None


def parse_wrk_output(filepath):
    """Parse wrk output file to extract metrics"""
    try:
        with open(filepath, 'r') as f:
            content = f.read()

        metrics = {
            "raw_output": content,
            "requests_per_sec": None,
            "transfer_per_sec": None,
            "latency_avg": None,
            "latency_stdev": None,
            "latency_max": None,
            "latency_p50": None,
            "latency_p75": None,
            "latency_p90": None,
            "latency_p99": None,
            "total_requests": None,
            "total_transfer": None,
        }

        # Parse requests/sec
        match = re.search(r'Requests/sec:\s+([\d.]+)', content)
        if match:
            metrics["requests_per_sec"] = float(match.group(1))

        # Parse transfer/sec
        match = re.search(r'Transfer/sec:\s+([\d.]+\w+)', content)
        if match:
            metrics["transfer_per_sec"] = match.group(1)

        # Parse latency distribution
        match = re.search(r'Latency\s+([\d.]+)(\w+)\s+([\d.]+)(\w+)\s+([\d.]+)(\w+)', content)
        if match:
            metrics["latency_avg"] = match.group(1) + match.group(2)
            metrics["latency_stdev"] = match.group(3) + match.group(4)
            metrics["latency_max"] = match.group(5) + match.group(6)

        # Parse percentiles if available
        percentile_matches = re.findall(r'(\d+)%\s+([\d.]+)(\w+)', content)
        for pct, val, unit in percentile_matches:
            if pct == '50':
                metrics["latency_p50"] = val + unit
            elif pct == '75':
                metrics["latency_p75"] = val + unit
            elif pct == '90':
                metrics["latency_p90"] = val + unit
            elif pct == '99':
                metrics["latency_p99"] = val + unit

        # Parse total requests
        match = re.search(r'(\d+) requests in', content)
        if match:
            metrics["total_requests"] = int(match.group(1))

        return metrics
    except Exception as e:
        print(f"Error parsing {filepath}: {e}")
        return None


def calculate_percentile(data, percentile):
    """Calculate percentile from data"""
    if not data:
        return None
    sorted_data = sorted(data)
    index = int(len(sorted_data) * percentile / 100)
    return sorted_data[min(index, len(sorted_data) - 1)]


def aggregate_metrics(results):
    """Aggregate metrics by test type and service mesh"""
    aggregated = {}

    for result in results:
        test_type = result.get('test_type', 'unknown')
        mesh_type = result.get('mesh_type', 'baseline')

        key = f"{test_type}_{mesh_type}"

        if key not in aggregated:
            aggregated[key] = {
                'test_type': test_type,
                'mesh_type': mesh_type,
                'runs': [],
                'avg_throughput': None,
                'avg_latency': None,
                'p95_latency': None,
                'p99_latency': None,
                'success_rate': None,
            }

        aggregated[key]['runs'].append(result)

    # Calculate aggregates
    for key, data in aggregated.items():
        runs = data['runs']

        # Extract throughput values
        throughputs = []
        latencies = []

        for run in runs:
            if 'metrics' in run:
                if 'requests_per_sec' in run['metrics'] and run['metrics']['requests_per_sec']:
                    throughputs.append(run['metrics']['requests_per_sec'])
                if 'avg_latency_ms' in run['metrics'] and run['metrics']['avg_latency_ms']:
                    latencies.append(run['metrics']['avg_latency_ms'])

        if throughputs:
            data['avg_throughput'] = statistics.mean(throughputs)
        if latencies:
            data['avg_latency'] = statistics.mean(latencies)
            data['p95_latency'] = calculate_percentile(latencies, 95)
            data['p99_latency'] = calculate_percentile(latencies, 99)

    return aggregated


def generate_comparison_table(aggregated_data):
    """Generate HTML comparison table"""
    # Group by test type
    by_test_type = {}
    for key, data in aggregated_data.items():
        test_type = data['test_type']
        if test_type not in by_test_type:
            by_test_type[test_type] = []
        by_test_type[test_type].append(data)

    html = ""
    for test_type, meshes in by_test_type.items():
        html += f"<h3>{test_type.upper()} Performance</h3>"
        html += """
        <table>
            <tr>
                <th>Service Mesh</th>
                <th>Avg Throughput</th>
                <th>Avg Latency</th>
                <th>P95 Latency</th>
                <th>P99 Latency</th>
                <th>Runs</th>
            </tr>
        """

        for mesh_data in sorted(meshes, key=lambda x: x['mesh_type']):
            mesh_type = mesh_data['mesh_type']
            throughput = f"{mesh_data['avg_throughput']:.2f} req/s" if mesh_data['avg_throughput'] else "N/A"
            avg_lat = f"{mesh_data['avg_latency']:.2f} ms" if mesh_data['avg_latency'] else "N/A"
            p95_lat = f"{mesh_data['p95_latency']:.2f} ms" if mesh_data['p95_latency'] else "N/A"
            p99_lat = f"{mesh_data['p99_latency']:.2f} ms" if mesh_data['p99_latency'] else "N/A"

            html += f"""
            <tr>
                <td><strong>{mesh_type}</strong></td>
                <td>{throughput}</td>
                <td>{avg_lat}</td>
                <td>{p95_lat}</td>
                <td>{p99_lat}</td>
                <td>{len(mesh_data['runs'])}</td>
            </tr>
            """

        html += "</table>"

    return html


def generate_chart_data(aggregated_data):
    """Generate JavaScript data for charts"""
    # Group by test type
    by_test_type = {}
    for key, data in aggregated_data.items():
        test_type = data['test_type']
        if test_type not in by_test_type:
            by_test_type[test_type] = {'labels': [], 'throughput': [], 'latency': []}

        by_test_type[test_type]['labels'].append(data['mesh_type'])
        by_test_type[test_type]['throughput'].append(data['avg_throughput'] or 0)
        by_test_type[test_type]['latency'].append(data['avg_latency'] or 0)

    return json.dumps(by_test_type)


def generate_html_report(results, output_file):
    """Generate enhanced HTML report with charts and metrics"""

    # Aggregate data
    aggregated = aggregate_metrics(results)
    comparison_table = generate_comparison_table(aggregated)
    chart_data = generate_chart_data(aggregated)

    html = f"""
<!DOCTYPE html>
<html>
<head>
    <title>Service Mesh Benchmark Report</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@3.9.1/dist/chart.min.js"></script>
    <style>
        body {{
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
        }}
        .container {{
            max-width: 1400px;
            margin: 0 auto;
            background-color: white;
            padding: 30px;
            box-shadow: 0 0 20px rgba(0,0,0,0.1);
            border-radius: 8px;
        }}
        h1 {{
            color: #333;
            border-bottom: 3px solid #4CAF50;
            padding-bottom: 10px;
        }}
        h2 {{
            color: #666;
            margin-top: 40px;
            border-bottom: 2px solid #e0e0e0;
            padding-bottom: 8px;
        }}
        h3 {{
            color: #777;
            margin-top: 25px;
        }}
        table {{
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }}
        th, td {{
            border: 1px solid #ddd;
            padding: 12px;
            text-align: left;
        }}
        th {{
            background-color: #4CAF50;
            color: white;
            font-weight: 600;
        }}
        tr:nth-child(even) {{
            background-color: #f9f9f9;
        }}
        tr:hover {{
            background-color: #f5f5f5;
        }}
        .metric {{
            display: inline-block;
            margin: 10px 20px 10px 0;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            border-radius: 8px;
            color: white;
            min-width: 150px;
        }}
        .metric-label {{
            font-weight: 600;
            font-size: 14px;
            opacity: 0.9;
        }}
        .metric-value {{
            font-size: 28px;
            font-weight: bold;
            margin-top: 8px;
        }}
        pre {{
            background-color: #f5f5f5;
            padding: 15px;
            border-radius: 5px;
            overflow-x: auto;
            border-left: 4px solid #4CAF50;
        }}
        .chart-container {{
            margin: 30px 0;
            padding: 20px;
            background-color: #fafafa;
            border-radius: 8px;
        }}
        canvas {{
            max-height: 400px;
        }}
        .summary-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin: 20px 0;
        }}
        .summary-card {{
            padding: 20px;
            background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
            border-radius: 8px;
            color: white;
            text-align: center;
        }}
        .summary-card h4 {{
            margin: 0 0 10px 0;
            font-size: 14px;
            opacity: 0.9;
        }}
        .summary-card .value {{
            font-size: 32px;
            font-weight: bold;
        }}
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Service Mesh Benchmark Report</h1>
        <p><strong>Generated:</strong> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>

        <h2>📊 Executive Summary</h2>
        <div class="summary-grid">
            <div class="summary-card">
                <h4>Total Tests</h4>
                <div class="value">{len(results)}</div>
            </div>
            <div class="summary-card" style="background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);">
                <h4>Test Types</h4>
                <div class="value">{len(set(r.get('test_type', 'unknown') for r in results))}</div>
            </div>
            <div class="summary-card" style="background: linear-gradient(135deg, #43e97b 0%, #38f9d7 100%);">
                <h4>Service Meshes</h4>
                <div class="value">{len(set(r.get('mesh_type', 'baseline') for r in results))}</div>
            </div>
        </div>

        <h2>📈 Performance Comparison</h2>
        {comparison_table}

        <h2>📉 Visualizations</h2>
        <div class="chart-container">
            <h3>Throughput Comparison</h3>
            <canvas id="throughputChart"></canvas>
        </div>

        <div class="chart-container">
            <h3>Latency Comparison</h3>
            <canvas id="latencyChart"></canvas>
        </div>

        <h2>📋 Detailed Test Results</h2>
        <table>
            <tr>
                <th>Test Type</th>
                <th>Service Mesh</th>
                <th>Timestamp</th>
                <th>Status</th>
                <th>Key Metrics</th>
            </tr>
"""

    for result in sorted(results, key=lambda x: (x.get('test_type', ''), x.get('timestamp', ''))):
        test_type = result.get('test_type', 'Unknown')
        mesh_type = result.get('mesh_type', 'baseline')
        timestamp = result.get('timestamp', 'N/A')
        status = "✅ Completed" if result else "❌ Failed"

        # Extract key metrics
        metrics_summary = ""
        if 'metrics' in result:
            metrics = result['metrics']
            if 'requests_per_sec' in metrics:
                metrics_summary += f"RPS: {metrics['requests_per_sec']:.2f}<br>"
            if 'avg_latency_ms' in metrics:
                metrics_summary += f"Latency: {metrics['avg_latency_ms']:.2f}ms<br>"
            if 'throughput_msg_per_sec' in metrics:
                metrics_summary += f"Throughput: {metrics['throughput_msg_per_sec']:.2f} msg/s<br>"

        html += f"""
            <tr>
                <td><strong>{test_type}</strong></td>
                <td>{mesh_type}</td>
                <td>{timestamp}</td>
                <td>{status}</td>
                <td>{metrics_summary or 'N/A'}</td>
            </tr>
"""

    html += f"""
        </table>

        <h2>💡 Recommendations</h2>
        <ul>
            <li><strong>Baseline Comparison:</strong> Compare service mesh performance against baseline (no-mesh) to calculate overhead</li>
            <li><strong>Latency Analysis:</strong> Review P95 and P99 latencies to understand tail latency behavior</li>
            <li><strong>Resource Utilization:</strong> Monitor control plane and data plane (sidecar) CPU/memory usage</li>
            <li><strong>Throughput Impact:</strong> Analyze throughput degradation percentage for each service mesh</li>
            <li><strong>Error Rates:</strong> Check for any failed requests or connection errors during testing</li>
            <li><strong>Scaling Behavior:</strong> Test performance under varying load conditions</li>
        </ul>
    </div>

    <script>
        const chartData = {chart_data};

        // Generate throughput chart
        const throughputLabels = [];
        const throughputDatasets = [];
        const colors = ['#667eea', '#764ba2', '#f093fb', '#f5576c', '#4facfe', '#00f2fe'];

        let colorIndex = 0;
        for (const [testType, data] of Object.entries(chartData)) {{
            throughputLabels.push(...data.labels);
            throughputDatasets.push({{
                label: testType,
                data: data.throughput,
                backgroundColor: colors[colorIndex % colors.length],
                borderColor: colors[colorIndex % colors.length],
                borderWidth: 2
            }});
            colorIndex++;
        }}

        new Chart(document.getElementById('throughputChart'), {{
            type: 'bar',
            data: {{
                labels: Array.from(new Set(throughputLabels)),
                datasets: throughputDatasets
            }},
            options: {{
                responsive: true,
                maintainAspectRatio: true,
                scales: {{
                    y: {{
                        beginAtZero: true,
                        title: {{
                            display: true,
                            text: 'Requests/sec'
                        }}
                    }}
                }},
                plugins: {{
                    legend: {{
                        display: true,
                        position: 'top'
                    }}
                }}
            }}
        }});

        // Generate latency chart
        const latencyDatasets = [];
        colorIndex = 0;
        for (const [testType, data] of Object.entries(chartData)) {{
            latencyDatasets.push({{
                label: testType,
                data: data.latency,
                backgroundColor: colors[colorIndex % colors.length],
                borderColor: colors[colorIndex % colors.length],
                borderWidth: 2
            }});
            colorIndex++;
        }}

        new Chart(document.getElementById('latencyChart'), {{
            type: 'bar',
            data: {{
                labels: Array.from(new Set(throughputLabels)),
                datasets: latencyDatasets
            }},
            options: {{
                responsive: true,
                maintainAspectRatio: true,
                scales: {{
                    y: {{
                        beginAtZero: true,
                        title: {{
                            display: true,
                            text: 'Latency (ms)'
                        }}
                    }}
                }},
                plugins: {{
                    legend: {{
                        display: true,
                        position: 'top'
                    }}
                }}
            }}
        }});
    </script>
</body>
</html>
"""

    with open(output_file, 'w') as f:
        f.write(html)

    print(f"HTML report generated: {output_file}")


def main():
    parser = argparse.ArgumentParser(description='Generate service mesh benchmark reports')
    parser.add_argument('--results-dir', default='benchmarks/results',
                        help='Directory containing benchmark results')
    parser.add_argument('--output', default='benchmarks/results/report.html',
                        help='Output report file')
    parser.add_argument('--format', choices=['html', 'json', 'csv'], default='html',
                        help='Report format')

    args = parser.parse_args()

    results_dir = Path(args.results_dir)
    if not results_dir.exists():
        print(f"Results directory not found: {results_dir}")
        print("Creating results directory...")
        results_dir.mkdir(parents=True, exist_ok=True)
        return

    print(f"Scanning for results in: {results_dir}")

    # Collect all JSON result files
    results = []
    for json_file in results_dir.glob('*.json'):
        data = load_json_file(json_file)
        if data:
            results.append(data)

    print(f"Found {len(results)} result files")

    if not results:
        print("No results found! Run some benchmarks first.")
        return

    # Generate report based on format
    if args.format == 'html':
        generate_html_report(results, args.output)
    elif args.format == 'json':
        output_data = {
            "generated_at": datetime.now().isoformat(),
            "total_tests": len(results),
            "results": results,
            "aggregated": aggregate_metrics(results)
        }
        with open(args.output, 'w') as f:
            json.dump(output_data, f, indent=2)
        print(f"JSON report generated: {args.output}")
    elif args.format == 'csv':
        # Enhanced CSV export
        import csv
        with open(args.output, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['Test Type', 'Service Mesh', 'Timestamp', 'Throughput', 'Latency', 'Status'])
            for result in results:
                throughput = result.get('metrics', {}).get('requests_per_sec', 'N/A')
                latency = result.get('metrics', {}).get('avg_latency_ms', 'N/A')
                writer.writerow([
                    result.get('test_type', 'Unknown'),
                    result.get('mesh_type', 'baseline'),
                    result.get('timestamp', 'N/A'),
                    throughput,
                    latency,
                    'Completed'
                ])
        print(f"CSV report generated: {args.output}")


if __name__ == '__main__':
    main()
