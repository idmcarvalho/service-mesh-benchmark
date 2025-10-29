#!/bin/bash
set -e
echo "Running all benchmarks..."
make deploy-workloads
echo "Waiting for workloads to be ready..."
sleep 30
make test-all
make collect-metrics
make generate-report
echo "Benchmarks complete! Check benchmarks/results/ for results"
