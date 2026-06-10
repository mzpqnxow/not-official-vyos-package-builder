#!/usr/bin/env bash
# Build one or more Debian packages (and their build-deps) from source inside
# the vyos-build:current container, then collect the .debs into packages-out/
# and re-index the local APT repo.
#
# Usage:   scripts/build-pkg.sh <package-name> [<package-name> ...]
# Example: scripts/build-pkg.sh lsof forkstat
#
# Env:
#   WITH_DBGSYM=1   also build the -dbgsym debug-symbol packages (default: off).
#                   They roughly double the disk/output per package and are only
#                   useful for gdb/crash backtraces, so they are suppressed by
#                   default via DEB_BUILD_OPTIONS=noautodbgsym.
#
# The vyos-build entrypoint drops to the UID that owns the mounted dir (your
# host user) and grants passwordless sudo. So: privileged steps use `sudo`;
# source fetch / dpkg-buildpackage / copy stay un-sudoed, leaving every .deb
# owned by you (no chown-back needed).
#
# Note: this builds the TARGET package(s) from source. To also build a missing
# RUNTIME dependency from source, inspect:
#     dpkg-deb -f packages-out/<pkg>_*.deb Depends
# and re-run this script for any dep not already in the VyOS base or packages-out/.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <package-name> [<package-name> ...]" >&2
  exit 2
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="docker.io/vyos/vyos-build:current"
WITH_DBGSYM="${WITH_DBGSYM:-0}"

mkdir -p "${PROJECT_ROOT}/packages-out"

echo ">> Building from source: $*"

sudo podman run --rm \
  --privileged \
  -v "${PROJECT_ROOT}":/work \
  -w /work \
  -e WITH_DBGSYM="${WITH_DBGSYM}" \
  "${IMAGE}" \
  bash -euo pipefail -c '
    pkgs="$*"

    # Enable Debian source repos for the SAME suite the container uses.
    . /etc/os-release
    printf "deb-src http://deb.debian.org/debian %s main contrib non-free non-free-firmware\n" \
      "${VERSION_CODENAME}" | sudo tee /etc/apt/sources.list.d/deb-src.list >/dev/null
    sudo apt-get update
    # Tools needed to build as non-root and to index the repo.
    sudo apt-get install -y --no-install-recommends fakeroot dpkg-dev

    # Suppress -dbgsym debug-symbol packages unless explicitly requested. These
    # are produced automatically by debhelper (dh_strip); noautodbgsym is the
    # documented opt-out. Saves roughly half the output/disk per package.
    if [ "${WITH_DBGSYM}" != "1" ]; then
      export DEB_BUILD_OPTIONS="${DEB_BUILD_OPTIONS:+${DEB_BUILD_OPTIONS} }noautodbgsym"
      echo ">> dbgsym packages disabled (set WITH_DBGSYM=1 to include them)"
    fi

    mkdir -p /work/.build-src
    # Fault-tolerant loop: a failure in one package must not abort the batch, and
    # the repo must still re-index from whatever succeeded. errexit is honored
    # INSIDE each per-package subshell (so a package fails fast at its first bad
    # step) but disabled in the loop body so the batch continues.
    set +e
    ok=""; failed=""
    for pkg in $pkgs; do
      echo ">> [$pkg] fetching source + build-deps"
      workdir="/work/.build-src/${pkg}"
      rm -rf "$workdir" && mkdir -p "$workdir"
      (
        set -e
        cd "$workdir"
        apt-get source "$pkg"                 # as user -> files owned by you
        sudo apt-get build-dep -y "$pkg"      # installs build-deps system-wide
        srcdir=$(find . -mindepth 1 -maxdepth 1 -type d | head -n1)
        echo ">> [$pkg] building in ${srcdir}"
        ( cd "$srcdir" && dpkg-buildpackage -us -uc -b )   # fakeroot, as user
        cp ./*.deb /work/packages-out/
      )
      if [ $? -eq 0 ]; then
        ok="${ok} ${pkg}"
      else
        echo ">> [$pkg] FAILED — continuing with the rest" 1>&2
        failed="${failed} ${pkg}"
      fi
    done
    set -e

    # Re-index the flat local repo so apt can resolve from it (always, so the
    # packages that did build are installable even if others failed).
    cd /work/packages-out
    dpkg-scanpackages -m . | gzip -9c > Packages.gz
    echo ">> packages-out/ now contains:"
    ls -1 ./*.deb
    echo ">> built OK:${ok:- (none)}"
    if [ -n "${failed}" ]; then echo ">> FAILED:${failed}" 1>&2; fi
    # Non-zero overall exit if anything failed (repo is still indexed above).
    [ -z "${failed}" ]
  ' _ "$@"

echo ">> Done. Local repo at: ${PROJECT_ROOT}/packages-out"