#!/usr/bin/env bash
# Build every package named in a list file (default: scripts/packages.list) by
# feeding the whole set to build-pkg.sh in ONE container run — so apt is set up
# once and the repo is re-indexed once at the end.
#
# Usage:   scripts/build-all.sh [list-file]
# Example: scripts/build-all.sh
#          scripts/build-all.sh scripts/my-other.list
#
# Env (passed straight through to build-pkg.sh):
#   WITH_DBGSYM=1   also build -dbgsym debug packages (default: off).
#
# The list file format: one source-package name per line; blank lines and
# everything after a '#' are ignored.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST="${1:-${PROJECT_ROOT}/scripts/packages.list}"

if [[ ! -f "${LIST}" ]]; then
  echo "error: package list not found: ${LIST}" >&2
  exit 1
fi

# Strip comments + surrounding whitespace, drop blank lines.
mapfile -t pkgs < <(sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "${LIST}" \
                    | grep -v '^$')

if (( ${#pkgs[@]} == 0 )); then
  echo "error: no packages listed in ${LIST} (all blank/commented?)" >&2
  exit 1
fi

echo ">> Building ${#pkgs[@]} package(s) from ${LIST}:"
printf '     %s\n' "${pkgs[@]}"

# Hand off to the existing builder (inherits WITH_DBGSYM from the environment).
exec "${PROJECT_ROOT}/scripts/build-pkg.sh" "${pkgs[@]}"
