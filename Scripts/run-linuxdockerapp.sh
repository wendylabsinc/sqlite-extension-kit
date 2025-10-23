#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$REPO_ROOT/Examples/LinuxDockerApp"
LOG_DIR="$APP_DIR/.logs"

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +"%Y%m%d-%H%M%S")-run.log"

PACKAGE_RESOLVED="$APP_DIR/Package.resolved"
if [[ -f "$PACKAGE_RESOLVED" ]]; then
  rm -f "$PACKAGE_RESOLVED"
fi

echo "Running LinuxDockerApp (logs: $LOG_FILE)"

if ! swift run --package-path "$APP_DIR" LinuxDockerApp 2>&1 | tee "$LOG_FILE"; then
  echo "LinuxDockerApp execution failed. See log: $LOG_FILE" >&2
  exit 1
fi

if [[ -f "$PACKAGE_RESOLVED" ]]; then
  rm -f "$PACKAGE_RESOLVED"
fi

required_patterns=(
  "reversed:"
  "word_count:"
  "trimmed:"
)

for pattern in "${required_patterns[@]}"; do
  if ! grep -q "$pattern" "$LOG_FILE"; then
    echo "Expected output containing '$pattern' not found in log $LOG_FILE" >&2
    exit 1
  fi
done

echo "LinuxDockerApp completed successfully. Log saved to $LOG_FILE"
