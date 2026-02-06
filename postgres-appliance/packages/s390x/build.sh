#!/bin/bash
# Build postgresql-*-jit packages for s390x
# Requires: docker buildx, QEMU binfmt support

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Building PostgreSQL JIT packages for s390x ==="
echo "This may take 30-60 minutes with QEMU emulation..."

# Ensure buildx is available
docker buildx version >/dev/null 2>&1 || {
    echo "Error: docker buildx required"
    exit 1
}

# Build and export .deb files
docker buildx build \
    --platform linux/s390x \
    -f Dockerfile.build-jit \
    -o type=local,dest=. \
    .

echo ""
echo "=== Build complete ==="
ls -la *.deb 2>/dev/null || echo "No .deb files found"
