#!/bin/bash

set -euo pipefail

echo "Running swift test to validate the package..."
swift test

echo "Building ExampleExtensions in release mode..."
swift build -c release --product ExampleExtensions

echo "Running LinuxDockerDemo executable..."
swift run -c release LinuxDockerDemo
