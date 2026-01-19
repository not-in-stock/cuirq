#!/usr/bin/env bash
set -euo pipefail

# Get the directory of the current script
SCRIPT_DIR=$(dirname "$(realpath "$0")")
PROJECT_ROOT=$(realpath "$SCRIPT_DIR/../..")

echo "=========================================="
echo " cuirq Counter Example"
echo "=========================================="
echo ""

# Build C++ bridge if needed
if [ ! -f "$PROJECT_ROOT/build/lib/libqmlbridge.dylib" ] && [ ! -f "$PROJECT_ROOT/build/lib/libqmlbridge.so" ]; then
    echo "Building C++ bridge..."
    cd "$PROJECT_ROOT"
    nix develop --command bash -c "cmake -B build -G Ninja && cmake --build build"
    echo "C++ bridge built"
    echo ""
fi

# Run Clojure app
echo "Starting the app..."
cd "$SCRIPT_DIR"
nix develop "$PROJECT_ROOT" --command clj -M:dev:run

