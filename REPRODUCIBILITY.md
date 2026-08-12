# Reproducibility notes

Goal for now: **reproducible inputs**, not byte-for-byte reproducible ISOs.
Two builds run months apart should pull the same inputs; they don't yet.

## Pinned today
- `Windows-10` GTK theme (`scripts/desktop.sh`): pinned to a fixed commit via
  `WINDOWS10_THEME_REF` (defaults to the `3.2.1` release commit, override-able).

## Still floating — pin next, roughly in priority order
1. **Debian/Ubuntu package versions** — `apt-get install` always resolves to
   whatever is latest in the mirror at build time. Two options once this
   matters enough to act on:
   - Point `debootstrap`/apt sources at a dated `snapshot.debian.org` (or
     Ubuntu's snapshot service) URL instead of the rolling mirror.
   - Or record the resolved package versions from a known-good build
     (`dpkg-query -W -f='${Package}=${Version}\n'` inside the chroot) and pin
     them explicitly in the `iso-config/packages/*.list` files
     (`package=version`), which `install_from_list` in `desktop.sh` would
     need a small update to pass through to `apt-get install`.
2. **`fastfetch` GitHub release** (`scripts/desktop.sh`) — currently fetches
   whatever tag `.../releases/latest` resolves to. Pin via an explicit
   `FASTFETCH_VERSION` env var, same pattern as `WINDOWS10_THEME_REF`.
3. **Wallpaper / logo / Plymouth assets** — `WALLPAPER_URL`, `LOGO_URL`,
   `PLYMOUTH_LOGO_URL` already point at specific files in this repo, so
   they're effectively pinned to whatever commit is checked out — just keep
   them that way (don't switch these to `.../main/...` URLs pulled from a
   different, unpinned checkout).
4. **`BASE_DISTRO`/`DEBIAN_VERSION`/`UBUNTU_VERSION`/`MINT_VERSION`** — these
   are already explicit vars with defaults (good), just worth calling out
   that "trixie"/"noble"/"22" will silently mean a different point-release
   as time passes; a dated snapshot (item 1) is what actually fixes this.

None of the above needs to happen before the next release — they're ordered
so the highest-payoff (packages) comes first.
