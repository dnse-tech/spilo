# PostgreSQL JIT Packages for s390x

Pre-built `postgresql-*-jit` packages for s390x architecture.

These packages provide the `postgresql-*-jit-llvm` virtual package required by many PGDG extensions in the s390x archive.

## Building

```bash
# Setup QEMU for s390x emulation (one-time)
docker run --privileged --rm tonistiigi/binfmt --install s390x

# Build packages
./build.sh

# Or manually:
docker buildx build --platform linux/s390x \
    -f Dockerfile.build-jit \
    -o type=local,dest=. \
    .
```

## Packages

| Package | Provides |
|---------|----------|
| postgresql-13-jit | postgresql-13-jit-llvm (= 15) |
| postgresql-14-jit | postgresql-14-jit-llvm (= 15) |
| postgresql-15-jit | postgresql-15-jit-llvm (= 15) |
| postgresql-16-jit | postgresql-16-jit-llvm (= 15) |
| postgresql-17-jit | postgresql-17-jit-llvm (= 15) |

## Usage in Spilo

These packages are automatically installed during the s390x build via `prepare.sh`.
