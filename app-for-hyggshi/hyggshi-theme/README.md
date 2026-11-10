# hyggshi-theme (bash + systemd timer)

A lightweight alternative to `hyggshi-theme-daemon` (C++/libxfconf, see
`app-for-hyggshi/hyggshi-theme-daemon/`). Instead of a persistent daemon running in the
background, this is a bash script triggered by a **systemd timer** every 5 minutes and
exits immediately — requiring no compile steps (no `libxfconf-0-dev`/`glib2.0-dev`
dependencies), with near-zero idle RAM consumption.

## Manual Installation (for local testing, outside ISO build)

```bash
sudo cp hyggshi-auto-theme /usr/local/bin/
sudo chmod +x /usr/local/bin/hyggshi-auto-theme
sudo cp hyggshi-auto-theme.service hyggshi-auto-theme.timer /etc/systemd/system/
sudo mkdir -p /etc/hyggshi
sudo cp theme.conf /etc/hyggshi/theme.conf

sudo systemctl daemon-reload
sudo systemctl enable --now hyggshi-auto-theme.timer
```

Verification:

```bash
systemctl status hyggshi-auto-theme.timer
sudo systemctl start hyggshi-auto-theme.service   # run immediately without waiting for timer
journalctl -u hyggshi-auto-theme.service -f
```

## Configuration

Edit `/etc/hyggshi/theme.conf` (system-wide) or create
`~/.config/hyggshi/theme.conf` (per-user override, no sudo needed):

```ini
MODE=auto
LIGHT_START=06:00
DARK_START=18:00
```

Set `MODE=light` or `MODE=dark` to force a specific theme, ignoring time schedules.

## How the system service changes user desktop wallpaper

`hyggshi-auto-theme.service` runs as a **system** service (not `--user`), so by default
it lacks the `DISPLAY` and `DBUS_SESSION_BUS_ADDRESS` environment variables of active graphical sessions. Calling `xfconf-query` directly would fail silently.

The `hyggshi-auto-theme` script automatically discovers active graphical user sessions via `loginctl`, then runs as `sudo -u <user>` with the corresponding session variables to invoke `/usr/local/bin/hyggshi-set-wallpaper.sh` (deployed by `scripts/branding.sh`), matching the behavior of `hyggshi-welcome`.

The script also tracks the last applied theme in `/var/lib/hyggshi-auto-theme/last-applied-<user>` to **avoid** redundant calls to `hyggshi-set-wallpaper.sh` (restarting xfdesktop) every 5 minutes if the theme has not changed — preventing periodic screen flickers.
