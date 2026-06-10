#!/usr/bin/env bash
# Build the generic VyOS ISO (amd64, native) inside the vyos-build:current container.
#
# Usage:   scripts/iso.sh
# Env:     BUILD_BY   build-by string  (default: user@user.com)
#          VERSION    version string   (default: 1.5-rolling-YYYYMMDD)
#          FLAVOR     build flavor      (default: generic)
#
# Output:  vyos-build/build/live-image-amd64.hybrid.iso
#
# The container drops to your UID and grants passwordless sudo; build-vyos-image
# genuinely needs root (debootstrap, loop mounts), so it runs under `sudo` here.
# Its output is then chowned back to the invoking user.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="docker.io/vyos/vyos-build:current"

BUILD_BY="${BUILD_BY:-user@user.com}"
VERSION="${VERSION:-1.5-rolling-$(date +%Y%m%d)}"
FLAVOR="${FLAVOR:-generic}"

if [[ ! -d "${PROJECT_ROOT}/vyos-build" ]]; then
  echo "error: ${PROJECT_ROOT}/vyos-build not found. Run the setup/clone step first." >&2
  exit 1
fi

echo ">> Building '${FLAVOR}' ISO  version=${VERSION}  build-by=${BUILD_BY}"

sudo podman run --rm \
  --privileged \
  -v "${PROJECT_ROOT}":/work \
  -w /work/vyos-build \
  -e BUILD_BY="${BUILD_BY}" -e VERSION="${VERSION}" -e FLAVOR="${FLAVOR}" \
  "${IMAGE}" \
  bash -euo pipefail -c '
    sudo ./build-vyos-image "${FLAVOR}" \
      --architecture amd64 \
      --build-by "${BUILD_BY}" \
      --version "${VERSION}"
    # build-vyos-image ran as root -> hand the artifacts back to your UID.
    sudo chown -R "$(id -u):$(id -g)" build
  '

# Verify the artifact actually exists before reporting success.
shopt -s nullglob
isos=( "${PROJECT_ROOT}/vyos-build/build/"*.iso )
if (( ${#isos[@]} == 0 )); then
  echo "error: build finished but no ISO found under vyos-build/build/" >&2
  exit 1
fi
echo ">> ISO(s) produced:"
ls -lh "${isos[@]}"
