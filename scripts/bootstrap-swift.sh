#!/usr/bin/env bash
#
# Install a Linux Swift toolchain so `swift test` can run in an agent sandbox.
#
# WHY THIS EXISTS
#
# InsightKit is a platform-free Swift package — 330 tests of clinical maths,
# baselines, scoring and parsers — but agent sandboxes ship no Swift, so every
# logic error had to be found by pushing and waiting ~2 minutes for CI. A single
# bad fixture then cost a full commit/push/wait/fix cycle, and each CI status
# check cost a ~450 KB API response.
#
# Two Darwin-only Foundation APIs used to make the package unbuildable on Linux
# (`Measurement.formatted` and `CFBooleanGetTypeID`). Both are now behind
# `#if canImport(Darwin)`, so the whole suite runs here. Verified: 330/330 pass
# on Swift 6.0.3 / Ubuntu 24.04.
#
# USAGE
#
#   ./scripts/bootstrap-swift.sh      # ~2 min, one download
#   source scripts/swift-env.sh       # puts swift on PATH
#   cd InsightKit && swift test --parallel
#
# Or, better, have the environment's setup script run this once at session
# start — then it costs nothing at all. See docs/deployment.md.
#
# Safe to re-run: exits immediately if the toolchain is already present.

set -euo pipefail

SWIFT_VERSION="${SWIFT_VERSION:-6.0.3}"
PREFIX="${SWIFT_PREFIX:-/opt/swift}"
UBUNTU="${SWIFT_UBUNTU:-ubuntu24.04}"
UBUNTU_PATH="${UBUNTU/./}"   # "ubuntu24.04" -> "ubuntu2404"

if [ -x "$PREFIX/usr/bin/swift" ]; then
    echo "Swift already present: $("$PREFIX/usr/bin/swift" --version | head -1)"
    exit 0
fi

# Match the toolchain CI uses where possible. CI is macOS/Xcode, so this is the
# nearest open-source release rather than an exact match — which is precisely
# why the app target still has to be compiled by CI and this only gates
# InsightKit.
URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/${UBUNTU_PATH}/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-${UBUNTU}.tar.gz"

echo "Downloading Swift ${SWIFT_VERSION} for ${UBUNTU} (~780 MB)..."
mkdir -p "$PREFIX"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if ! curl -fsSL -o "$tmp/swift.tar.gz" "$URL"; then
    echo "Download failed. If this sandbox has no outbound network, skip local"
    echo "testing and let CI be the gate — that is the documented fallback."
    exit 1
fi

tar xzf "$tmp/swift.tar.gz" -C "$PREFIX" --strip-components=1
echo "Installed: $("$PREFIX/usr/bin/swift" --version | head -1)"
echo
echo "Now run:  source scripts/swift-env.sh && cd InsightKit && swift test --parallel"
