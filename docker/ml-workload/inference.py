#!/usr/bin/env python3
"""ML Inference Job for Service Mesh Benchmarking"""

import numpy as np
import time

def main():
    print("Running inference...")

    # Generate test data
    data = np.random.rand(1000, 20)

    # Simulate inference processing
    time.sleep(5)

    print("Inference completed")

if __name__ == "__main__":
    main()
