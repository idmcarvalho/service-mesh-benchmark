#!/usr/bin/env python3
"""ML Training Job for Service Mesh Benchmarking"""

import numpy as np
from sklearn.ensemble import RandomForestClassifier
import time

def main():
    print("Starting ML training job...")

    # Generate synthetic dataset
    X = np.random.rand(10000, 20)
    y = np.random.randint(0, 2, 10000)

    # Train model
    model = RandomForestClassifier(n_estimators=100)
    start_time = time.time()
    model.fit(X, y)
    duration = time.time() - start_time

    print(f"Training completed in {duration:.2f} seconds")
    print(f"Model score: {model.score(X, y):.4f}")

if __name__ == "__main__":
    main()
