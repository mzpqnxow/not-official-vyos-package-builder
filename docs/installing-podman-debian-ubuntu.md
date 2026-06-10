# Installing Podman on Debian / Ubuntu (for dummies)

A step-by-step guide to installing Podman and verifying it works for **this
project**. The build scripts in [`scripts/`](../scripts/) run **`sudo podman`
(root Podman)** with `--privileged`, so that is the path this guide gets you to
first. (Rootless Podman is a nice thing to have, but this project does *not* use
it — see the [optional appendix](#appendix-running-rootless-optional--not-used-by-this-project).)

> **Which distro?** The steps are the same for Debian and Ubuntu. Where the
> version matters, it's called out. Newer is better: Debian 12 (bookworm)+ or
> Ubuntu 22.04+ ship a modern Podman and "just work". Older releases need an
> extra step (see [Troubleshooting](#troubleshooting)).

---

## 1. Install Podman

```bash
sudo apt-get update
sudo apt-get install -y podman
```

That's the whole install. Check the version (4.x or newer is ideal):

```bash
podman version
```

---

## 2. Verify it works the way this project uses it

The scripts call Podman through `sudo`, so test it the same way:

```bash
sudo podman run --rm docker.io/library/hello-world
```

You should see Podman pull the image and print a "Hello from ..." message. If
that works, **you're ready to use this repo** — head back to the
[README](../README.md) and run `scripts/build-pkg.sh <package>`.

> Note: `sudo podman` uses **root's** Podman storage and config, which is
> entirely separate from any rootless setup under your own user. You do *not*
> need the subuid/subgid steps in the appendix to use these scripts.

---

## Why this project uses `sudo podman`

To be clear about the reality: **every script in this repo runs `sudo podman run
--privileged`** — i.e. *root* Podman, not rootless. This is deliberate, not an
oversight:

- **The VyOS ISO build genuinely needs real root.** [`iso.sh`](../scripts/iso.sh)
  runs `build-vyos-image`, which calls `debootstrap`, mounts loop devices, and
  creates device nodes. Those are real kernel operations.
- **Rootless `--privileged` is not the same as host root.** A common
  misconception is that adding `--privileged` makes a rootless container
  all-powerful. It does not — rootless `--privileged` only lifts restrictions
  *inside your user namespace*; it cannot grant capabilities your real user
  doesn't have, so the loop-mount / `debootstrap` steps above would still fail.
  Running Podman as root (via `sudo`) is what provides them.
- **`serve.sh` defaults to port 80**, a privileged port that an unprivileged
  process can't bind without extra configuration.

Good news on file ownership: despite the `sudo`, the `vyos-build` container
entrypoint drops back to your host UID for the actual build, and the scripts
`chown` artifacts back to you — so your `.deb` files and ISOs end up owned by
**you**, not root.

If running things as root via `sudo` is a dealbreaker, making
[`build-pkg.sh`](../scripts/build-pkg.sh) work rootless is *plausible* (package
builds don't inherently need host root the way ISO builds do), but it isn't
supported today and would need testing — the scripts hard-code `sudo podman
--privileged` as written. The ISO build is the part that fundamentally needs
root and is unlikely to go rootless.

---

## Troubleshooting

**`hello-world` fails with a uid-mapping / `newuidmap` error.**
Install the helper for ID mapping, then retry:

```bash
sudo apt-get install -y uidmap
sudo podman run --rm docker.io/library/hello-world
```

(This matters mostly for rootless mode, but installing it is harmless.)

**Old Podman (3.x or older) behaves oddly / commands are missing.**
Older distro releases ship an old Podman. Upgrade the OS if you can. Otherwise,
on Ubuntu you can get a newer build from a PPA, or use the upstream
[Kubic/openSUSE OBS](https://podman.io/docs/installation#debian) packages — but
the cleanest fix is a newer Debian/Ubuntu release.

**"short-name did not resolve" when pulling an image.**
Use the fully-qualified image name including the registry, e.g.
`docker.io/library/hello-world` instead of just `hello-world`. The scripts in
this repo already use fully-qualified names like
`docker.io/vyos/vyos-build:current`.

**Build fails partway through with no obvious error.**
Check disk space with `df -h` — `.build-src/` and `packages-out/` grow fast, and
a full disk is the most common cause of mysterious build failures.

---

## Appendix: running rootless (optional — not used by this project)

You don't need any of this for the repo's scripts. It's here only as general
reference if you want to run *other* containers rootless (as your normal user,
no `sudo`).

**1. Give yourself subuid / subgid ranges.** Rootless containers map a *range*
of fake user IDs onto your single real user. Check whether you already have a
range:

```bash
grep "^$(whoami):" /etc/subuid /etc/subgid
```

If you see two lines (e.g. `youruser:100000:65536`) you're set. If not, add one:

```bash
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$(whoami)"
podman system migrate    # rebuild Podman's user mapping after the change
```

> Older system without `usermod --add-subuids`? Append by hand instead:
> ```bash
> echo "$(whoami):100000:65536" | sudo tee -a /etc/subuid
> echo "$(whoami):100000:65536" | sudo tee -a /etc/subgid
> ```

**2. (Optional) Enable lingering** so rootless containers survive logout / work
over SSH or cron:

```bash
sudo loginctl enable-linger "$(whoami)"
```

**3. Test rootless** — note: **no `sudo`** this time:

```bash
podman run --rm docker.io/library/hello-world
podman info --format '{{.Host.Security.Rootless}}'   # should print: true
```

If `Rootless` prints `true`, rootless mode works. Remember this is a *separate*
Podman from the `sudo podman` the project uses — running rootless here has no
effect on the build scripts.
