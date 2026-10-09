#!/bin/bash
# build-nexwm.sh — build HDE (the Hyggshi Desktop Environment, formerly NexDE / NexWM) from source and
# install it into a Debian rootfs: the "HDE" (X11) and "HDE (Wayland)" sessions on the login screen.
#
# Upstream: https://github.com/Hyggshi-OS-Research-Technology/NexWM
# Interface: run it as root INSIDE the chroot of the ISO (like desktop.sh), with variables:
#   NEXWM_REPO_URL   git URL of this repository   (default: https://github.com/Hyggshi-OS-Research-Technology/NexWM.git)
#   NEXWM_REF        branch or tag to build       (default: main)
#   SRC_DIR          where the source is cloned   (default: /tmp/nexwm-src)
#   PREFIX           install prefix               (default: /usr, like the .deb packages of the ISO)
#   DEBUG_MODE=true  set -x
#   NEXWM_LOCAL_SRC=DIR     build this checkout instead of cloning (CI)
#   HDE_RUNTIME=minimal     only what HDE needs to start (window manager, D-Bus, icons); default "full" adds what its
#                           features use when present: NetworkManager (Wi-Fi), PulseAudio/PipeWire tools (volume),
#                           power-profiles-daemon (power mode), labwc + grim + slurp (Wayland session), polkit agent,
#                           ddcutil (brightness of desktop monitors)
#   HDE_DEFAULT_SESSION=true   make HDE the default session of LightDM / SDDM
#   KEEP_BUILD_DEPS=true    keep the compiler and the -dev packages (smaller ISOs remove them: the default)
#
# The session files come from `make install` (Type=Application with absolute Exec/TryExec paths, which LightDM, SDDM
# and GDM all accept): /usr/share/xsessions/hde.desktop, /usr/share/xsessions/nexwm.desktop (HDE with NexWM, HDE's own
# window manager, built from this repository) and /usr/share/wayland-sessions/hde-wayland.desktop.
set -e
[ "${DEBUG_MODE:-}" = "true" ] && set -x
export DEBIAN_FRONTEND=noninteractive

: "${NEXWM_REPO_URL:=https://github.com/Hyggshi-OS-Research-Technology/NexWM.git}"
: "${NEXWM_REF:=main}"
: "${SRC_DIR:=/tmp/nexwm-src}"
: "${PREFIX:=/usr}"
: "${HDE_RUNTIME:=full}"

say() { printf '===== %s =====\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "run it as root (inside the chroot of the ISO)"
command -v apt-get >/dev/null 2>&1 || die "apt-get not found: this script is for Debian-based systems"

BUILD_DEPS="git ca-certificates build-essential pkg-config libgtk-3-dev libwnck-3-dev libxi-dev libxrandr-dev libx11-dev
            libgtk-layer-shell-dev libwayland-dev wayland-protocols libxcb1-dev"
# what HDE needs to start: a GTK window manager (title bars follow the theme and Dark mode), D-Bus, X tools used by the
# session (xset: screen blanking, xsetroot: the pointer), icons and SVG support
RUNTIME_MIN="metacity dbus dbus-x11 x11-xserver-utils adwaita-icon-theme librsvg2-common libglib2.0-bin"
# what its features use when present
RUNTIME_FULL="network-manager pulseaudio-utils power-profiles-daemon labwc xwayland grim slurp xdg-desktop-portal-gtk
              upower ddcutil libnotify-bin"
# one polkit authentication agent (the password window of "Install updates", disks, ...): the first one there is
POLKIT_AGENTS="polkit-gnome policykit-1-gnome lxpolkit mate-polkit"

installed() { dpkg-query -W -f='${Status}\n' "$1" 2>/dev/null | grep -q "install ok installed"; }
# a package apt can install here (known names without a candidate, e.g. removed ones, do not count)
available() {
    c=$(apt-cache policy "$1" 2>/dev/null | sed -n 's/^ *Candidate: *//p' | head -n 1)
    [ -n "$c" ] && [ "$c" != "(none)" ]
}

say "packages"
apt-get update
NEW_BUILD_DEPS=""
for p in $BUILD_DEPS; do installed "$p" || NEW_BUILD_DEPS="$NEW_BUILD_DEPS $p"; done
# what HDE needs: all of it, or stop
# shellcheck disable=SC2086  # lists of package names
apt-get install -y --no-install-recommends $BUILD_DEPS $RUNTIME_MIN
# what its features use: each one that can be installed (a package missing or refused here is not worth failing for)
if [ "$HDE_RUNTIME" != "minimal" ]; then
    OPT=""
    for p in $RUNTIME_FULL; do
        if available "$p"; then OPT="$OPT $p"; else echo "note: $p is not available here: skipped"; fi
    done
    for a in $POLKIT_AGENTS; do
        if available "$a"; then OPT="$OPT $a"; break; fi
    done
    # shellcheck disable=SC2086
    if ! apt-get install -y --no-install-recommends $OPT; then
        for p in $OPT; do
            apt-get install -y --no-install-recommends "$p" || echo "note: $p could not be installed: skipped"
        done
    fi
fi

if [ -n "${NEXWM_LOCAL_SRC:-}" ]; then
    say "source: $NEXWM_LOCAL_SRC"
    [ -f "$NEXWM_LOCAL_SRC/Makefile" ] || die "$NEXWM_LOCAL_SRC is not a checkout of HDE (no Makefile)"
    SRC="$NEXWM_LOCAL_SRC"
else
    say "clone $NEXWM_REPO_URL @ $NEXWM_REF"
    rm -rf "$SRC_DIR"
    git clone --branch "$NEXWM_REF" --depth=1 "$NEXWM_REPO_URL" "$SRC_DIR" ||
        die "clone failed (wrong NEXWM_REPO_URL / NEXWM_REF, or no network): '$NEXWM_REPO_URL' '$NEXWM_REF'"
    SRC="$SRC_DIR"
fi

say "make"
make -C "$SRC" -j"$(nproc)" all
PROGRAMS="hde-session hde-desktop hde-panel hde-settings hde-hotkeys hde-xsettings hde-screenshot hde-files hde-media hde-choose hde-cmd nexwm"
for p in $PROGRAMS; do
    [ -x "$SRC/build/$p" ] || die "build/$p was not built (see the make output above)"
done

say "make install PREFIX=$PREFIX"
make -C "$SRC" install PREFIX="$PREFIX"
for p in $PROGRAMS hde-start; do
    [ -x "$PREFIX/bin/$p" ] || die "$PREFIX/bin/$p is missing after make install"
done
for f in /usr/share/xsessions/hde.desktop /usr/share/xsessions/nexwm.desktop \
         /usr/share/wayland-sessions/hde-wayland.desktop; do
    [ -f "$f" ] || die "$f is missing after make install"
    grep -q "^Exec=$PREFIX/bin/hde-start" "$f" || die "$f does not start $PREFIX/bin/hde-start"
done
[ -f /usr/share/applications/hde-cmd.desktop ] || die "/usr/share/applications/hde-cmd.desktop is missing after make install"
grep -q "^Exec=$PREFIX/bin/hde-cmd$" /usr/share/applications/hde-cmd.desktop || die "hde-cmd.desktop does not start $PREFIX/bin/hde-cmd"

# what the old NexDE script left: its programs no longer exist, so the login screen would offer a broken session.
if [ -e /usr/share/xsessions/nexwm.desktop ] && ! grep -q "^Exec=$PREFIX/bin/hde-start" /usr/share/xsessions/nexwm.desktop; then
    echo "removing /usr/share/xsessions/nexwm.desktop (the old NexDE session)"
    rm -f /usr/share/xsessions/nexwm.desktop
fi
if [ -e "$PREFIX/bin/start-nexde" ]; then echo "removing $PREFIX/bin/start-nexde (old NexDE)"; rm -f "$PREFIX/bin/start-nexde"; fi

if [ "${HDE_DEFAULT_SESSION:-}" = "true" ]; then
    say "HDE as the default session"
    if [ -d /etc/lightdm ]; then
        mkdir -p /etc/lightdm/lightdm.conf.d
        printf '[Seat:*]\nuser-session=hde\n' > /etc/lightdm/lightdm.conf.d/50-hde.conf
    fi
    if [ -d /etc/sddm.conf.d ] || command -v sddm >/dev/null 2>&1; then
        mkdir -p /etc/sddm.conf.d
        printf '[Autologin]\nSession=hde.desktop\n' > /etc/sddm.conf.d/50-hde.conf
    fi
fi

# keep every library the programs use: they came in as dependencies of the -dev packages, which go away below
say "runtime libraries"
LIBS=$(for b in "$PREFIX"/bin/hde-*; do ldd "$b" 2>/dev/null | awk '$2 == "=>" && $3 ~ /^\// { print $3 }'; done | sort -u)
PKGS=""
for l in $LIBS; do
    p=""
    for f in "$l" "$(readlink -f "$l")"; do
        p=$(dpkg -S "$f" 2>/dev/null | grep -v '^diversion' | head -n 1 | sed -n 's/^\([^:, ]*\)[:,].*/\1/p')
        [ -n "$p" ] && break
    done
    [ -n "$p" ] && case " $PKGS " in *" $p "*) ;; *) PKGS="$PKGS $p" ;; esac
done
# shellcheck disable=SC2086
if [ -n "$PKGS" ] && ! apt-mark manual $PKGS > /dev/null; then
    echo "note: apt-mark could not mark every library package as manually installed"
fi
echo "kept:$PKGS"

if [ "${KEEP_BUILD_DEPS:-}" != "true" ] && [ -n "$NEW_BUILD_DEPS" ]; then
    say "remove the build tools installed by this script"
    # shellcheck disable=SC2086
    apt-get purge -y --autoremove $NEW_BUILD_DEPS
fi
[ -z "${NEXWM_LOCAL_SRC:-}" ] && rm -rf "$SRC_DIR"

say "check"
missing=$(for b in "$PREFIX"/bin/hde-* "$PREFIX"/bin/nexwm; do ldd "$b" 2>/dev/null | grep "not found" | sed "s|^|$b: |"; done)
[ -z "$missing" ] || die "libraries missing after the build tools were removed:
$missing"
"$PREFIX/bin/hde-settings" --version 2>/dev/null || true
"$PREFIX/bin/hde-cmd" --version 2>/dev/null || true
"$PREFIX/bin/hde-choose" --version 2>/dev/null || true
echo "OK: HDE is installed in $PREFIX/bin; sessions: /usr/share/xsessions/hde.desktop (HDE)," \
     "/usr/share/xsessions/nexwm.desktop (HDE with NexWM, its own window manager)," \
     "/usr/share/wayland-sessions/hde-wayland.desktop (HDE (Wayland), with labwc)"
say "build-nexwm.sh done"
