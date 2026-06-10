#!/usr/bin/env bash
# Drop into an interactive shell inside the vyos-build:current container.
# The project root is mounted at /work; cwd is the cloned vyos-build repo.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="docker.io/vyos/vyos-build:current"

exec sudo podman run --rm -it \
  --privileged \
  -v "${PROJECT_ROOT}":/work \
  -w /work/vyos-build \
  "${IMAGE}" bash
