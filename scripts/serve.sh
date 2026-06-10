#!/usr/bin/env bash
# Serve the accumulating local APT repo (packages-out/) over HTTP so a VyOS router
# can consume it as an apt source instead of copying files around.
#
# The repo in packages-out/ is already a valid *flat* APT repo (.deb files plus a
# Packages.gz index built by build-pkg.sh). apt is transport-agnostic, so the same
# repo that worked over file:/ works over http:/ with no changes — this script just
# puts a stock nginx in front of it.
#
# Usage:
#   scripts/serve.sh            # start the HTTP server (detached)
#   scripts/serve.sh stop       # stop and remove the server
#   scripts/serve.sh status     # show whether it is running
#
# Env:
#   PORT   host port to listen on   (default: 80 -> clean http://myserver/vyos/)
#
# On the router (replace 'myserver' with this host's reachable IP/DNS, and add the
# port if you changed PORT, e.g. http://myserver:8080/vyos/):
#   echo "deb [trusted=yes] http://myserver/vyos/ ./" \
#     | sudo tee /etc/apt/sources.list.d/local.list
#   sudo apt-get update
#   sudo apt-get install <pkg>
#
# The repo updates live (the bind mount is read-only but current): after building
# more packages with build-pkg.sh — which re-indexes Packages.gz — the router just
# needs another `apt-get update`. No restart of this server is required.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="docker.io/library/nginx:stable"
NAME="vyos-apt"
PORT="${PORT:-80}"

ACTION="${1:-start}"

case "${ACTION}" in
  stop)
    echo ">> Stopping ${NAME}"
    sudo podman stop "${NAME}" 2>/dev/null || echo "   (not running)"
    exit 0
    ;;
  status)
    sudo podman ps --filter "name=^${NAME}$" --format '{{.Names}}  {{.Status}}  {{.Ports}}'
    exit 0
    ;;
  start) ;;
  *)
    echo "usage: $0 [start|stop|status]   (env: PORT, default 80)" >&2
    exit 2
    ;;
esac

if [[ ! -d "${PROJECT_ROOT}/packages-out" ]]; then
  echo "error: ${PROJECT_ROOT}/packages-out not found. Build a package first (scripts/build-pkg.sh)." >&2
  exit 1
fi
if [[ ! -f "${PROJECT_ROOT}/packages-out/Packages.gz" ]]; then
  echo "warning: packages-out/Packages.gz missing — apt-get update will fail until you" >&2
  echo "         build a package (scripts/build-pkg.sh re-indexes the repo)." >&2
fi

# Replace any stale instance so the script is idempotent.
sudo podman rm -f "${NAME}" >/dev/null 2>&1 || true

echo ">> Serving packages-out/ as an HTTP apt source on port ${PORT}"
sudo podman run --rm -d --name "${NAME}" \
  -p "${PORT}:80" \
  -v "${PROJECT_ROOT}/packages-out":/usr/share/nginx/html/vyos:ro \
  -v "${PROJECT_ROOT}/scripts/nginx-autoindex.conf":/etc/nginx/conf.d/default.conf:ro \
  "${IMAGE}" >/dev/null

# Best-effort host address for the user to paste into the router's sources.list.
host_ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')"
host_ip="${host_ip:-<this-host-ip>}"
url_host="${host_ip}"
[[ "${PORT}" != "80" ]] && url_host="${host_ip}:${PORT}"

echo ">> Serving at: http://${url_host}/vyos/   (browse: open that URL)"
echo ">> On the VyOS router add this apt source:"
echo "     echo \"deb [trusted=yes] http://${url_host}/vyos/ ./\" | sudo tee /etc/apt/sources.list.d/local.list"
echo "     sudo apt-get update && sudo apt-get install <pkg>"
echo ">> Stop with: scripts/serve.sh stop"
