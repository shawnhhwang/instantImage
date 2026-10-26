#!/bin/bash
set -e

# Target flag parser
case "$1" in
    --intel|-i)
        echo "⚡️ Running Intel-only build..."
        ./build_intel.sh
        exit 0
        ;;
    --arm64|--apple-silicon|-a)
        echo "🍏 Running Apple Silicon-only build..."
        ./build_arm64.sh
        exit 0
        ;;
    --all|-u|*)
        echo "🚀 Running comprehensive dual-target & Universal build..."
        ./build_dual_versions.sh
        exit 0
        ;;
esac
