# Put the bootstrapped Swift toolchain on PATH. Source it, don't run it:
#
#   source scripts/swift-env.sh
#
# No-op when a system Swift already exists (a real Mac, or CI).
if ! command -v swift >/dev/null 2>&1 && [ -x "${SWIFT_PREFIX:-/opt/swift}/usr/bin/swift" ]; then
    export PATH="${SWIFT_PREFIX:-/opt/swift}/usr/bin:$PATH"
fi
