#!/usr/bin/env python3
"""
Service Mesh Benchmark Report Generator
Generates comprehensive reports from benchmark results
"""

import json
import glob
import os
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
    """Parse wrk output file"""
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        # Basic parsing - can be enhanced
        return {"raw_output": content}
    except Exception as e:
        print(f"Error parsing {filepath}: {e}")
        return None


def generate_html_report(results, output_file):
    """Generate HTML report"""
    html = f"""
<!DOCTYPE html>
<html>
<head>
    <title>Service Mesh Benchmark Report</title>
    <style>
        body {{
            font-family: Arial, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
        }}
        .container {{
            max-width: 1200px;
            margin: 0 auto;
            background-color: white;
            padding: 20px;
            box-shadow: 0 0 10px rgba(0,0,0,0.1);
        }}
        h1 {{
            color: #333;
            border-bottom: 2px solid #4CAF50;
            padding-bottom: 10px;
        }}
        h2 {{
            color: #666;
            margin-top: 30px;
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
        }}
        tr:nth-child(even) {{
            background-color: #f2f2f2;
        }}
        .metric {{
            display: inline-block;
            margin: 10px 20px 10px 0;
            padding: 15px;
            background-color: #e3f2fd;
            border-radius: 5px;
        }}
        .metric-label {{
            font-weight: bold;
            color: #1976d2;
        }}
        .metric-value {{
            font-size: 24px;
            color: #333;
        }}
        pre {{
            background-color: #f5f5f5;
            padding: 15px;
            border-radius: 5px;
            overflow-x: auto;
        }}
    </style>
</head>
<body>
    <div class="container">
        <h1>Service Mesh Benchmark Report</h1>
        <p><strong>Generated:</strong> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>

        <h2>Test Summary</h2>
        <div>
            <div class="metric">
                <div class="metric-label">Total Tests</div>
                <div class="metric-value">{len(results)}</div>
            </div>
        </div>

        <h2>Test Results</h2>
        <table>
            <tr>
                <th>Test Type</th>
                <th>Timestamp</th>
                <th>Status</th>
                <th>Details</th>
            </tr>
"""

    for result in results:
        test_type = result.get('test_type', 'Unknown')
        timestamp = result.get('timestamp', 'N/A')
        status = "Completed" if result else "Failed"

        html += f"""
            <tr>
                <td>{test_type}</td>
                <td>{timestamp}</td>
                <td>{status}</td>
                <td><pre>{json.dumps(result, indent=2)}</pre></td>
            </tr>
"""

    html += """
        </table>

        <h2>Recommendations</h2>
        <ul>
            <li>Review latency metrics for each service mesh</li>
            <li>Compare resource utilization across different configurations</li>
            <li>Analyze throughput differences between service meshes</li>
            <li>Check for any error rates or failed requests</li>
        </ul>
    </div>
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
        print("No results found!")
        return

    # Generate report based on format
    if args.format == 'html':
        generate_html_report(results, args.output)
    elif args.format == 'json':
        output_data = {
            "generated_at": datetime.now().isoformat(),
            "total_tests": len(results),
            "results": results
        }
        with open(args.output, 'w') as f:
            json.dump(output_data, f, indent=2)
        print(f"JSON report generated: {args.output}")
    elif args.format == 'csv':
        # Basic CSV export
        import csv
        with open(args.output, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['Test Type', 'Timestamp', 'Details'])
            for result in results:
                writer.writerow([
                    result.get('test_type', 'Unknown'),
                    result.get('timestamp', 'N/A'),
                    json.dumps(result)
                ])
        print(f"CSV report generated: {args.output}")


if __name__ == '__main__':
    main()
