# not-official-vyos-package-builder

Build extra Debian packages (and VyOS ISOs) from source inside the official
`vyos/vyos-build` container, collect the `.deb` files into a local flat APT
repo, and optionally serve that repo over HTTP so a VyOS router can `apt-get
install` from it.

> Not affiliated with or endorsed by the VyOS project but makes use of
> the official docker.io/vyos/vyos-build:current container

## Requirements

- `podman` (tested rootless; `docker` should work with minor tweaks) and `sudo`.
- **Lots of disk.** `./.build-src/` becomes very large during a build, and
  `packages-out/` grows with every package you add.
- The `vyos-build` repo cloned into `./vyos-build/` (needed for `iso.sh`).

## Quick start

```bash
# Build a single package (plus its build-deps) from source
scripts/build-pkg.sh tcpdump

# Build everything in scripts/packages.list in one container run
scripts/build-all.sh

# Serve the resulting repo over HTTP for a router to consume
scripts/serve.sh
```

The output lands in `packages-out/` — a valid *flat* APT repo (`.deb` files +
a `Packages.gz` index). Use it directly via `file:/`, or over HTTP via
`serve.sh`.

## Scripts

| Script | What it does |
| --- | --- |
| [`build-pkg.sh`](scripts/build-pkg.sh) | The core builder. Fetches one or more source packages and their build-deps, runs `dpkg-buildpackage` as your user inside the container, copies the `.deb`s into `packages-out/`, and re-indexes the repo. Fault-tolerant: a failed package is reported and skipped, the rest still build. |
| [`build-all.sh`](scripts/build-all.sh) | Thin batch wrapper. Reads a package list (default [`packages.list`](scripts/packages.list)) and hands the whole set to `build-pkg.sh` in a *single* container run, so apt is set up once and the repo is re-indexed once. |
| [`serve.sh`](scripts/serve.sh) | Puts a stock nginx in front of `packages-out/` so a router can use it as an HTTP apt source. Supports `start` / `stop` / `status`; prints the exact `sources.list` line to paste on the router. |
| [`iso.sh`](scripts/iso.sh) | Builds a generic VyOS ISO (amd64) via `build-vyos-image` in the container, then chowns the artifacts back to you and verifies an ISO was produced. |
| [`enter.sh`](scripts/enter.sh) | Drops you into an interactive shell inside the `vyos-build:current` container, with the project mounted at `/work` — handy for debugging a build by hand. |

### Data & config

| File | What it is |
| --- | --- |
| [`packages.list`](scripts/packages.list) | Curated list of Debian **source** package names to build (one per line; `#` comments and blanks ignored). An accumulating set you maintain — not a full mirror. |
| [`nginx-autoindex.conf`](scripts/nginx-autoindex.conf) | Minimal nginx site config bind-mounted by `serve.sh`. Enables directory browsing; deliberately avoids gzip so `Packages.gz` is served verbatim. |

## Environment variables

| Variable | Used by | Default | Effect |
| --- | --- | --- | --- |
| `WITH_DBGSYM` | `build-pkg.sh`, `build-all.sh` | `0` | Set to `1` to also build `-dbgsym` debug packages (roughly doubles output). |
| `PORT` | `serve.sh` | `80` | Host port for the HTTP repo. |
| `BUILD_BY` | `iso.sh` | `user@user.com` | `build-by` string stamped into the ISO. |
| `VERSION` | `iso.sh` | `1.5-rolling-<date>` | ISO version string. |
| `FLAVOR` | `iso.sh` | `generic` | ISO build flavor. |

## Using the repo on a VyOS router

After serving with `scripts/serve.sh`, on the router (`serve.sh` prints the
exact line with your host's IP filled in):

```bash
echo "deb [trusted=yes] http://<this-host>/vyos/ ./" \
  | sudo tee /etc/apt/sources.list.d/local.list
sudo apt-get update
sudo apt-get install <pkg>
```

The bind mount is live: after building more packages, the router only needs
another `apt-get update` — no server restart.
