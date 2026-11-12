#!/usr/bin/env bash
# ==============================================================================
# fetch_foss_apks.sh — Manifest-Driven FOSS Android TV APK Fetcher
# Wrapper around fetch_apps.py using config/apps.json
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Run manifest-driven Python fetcher
exec python3 "$SCRIPT_DIR/fetch_apps.py" \
    --manifest "$REPO_ROOT/config/apps.json" \
    --output-dir "$REPO_ROOT/downloads" \
    "$@"
