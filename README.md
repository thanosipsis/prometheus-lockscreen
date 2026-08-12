# Prometheus Lockscreen

A Prometheus-themed Quickshell v0.3.x lockscreen for Hyprland.

Status: source install, tested on Arch/CachyOS-style Hyprland sessions only.

The lockscreen uses `WlSessionLock` for the real session lock. Every monitor is covered. By default, the interactive UI appears on every monitor so a new user does not need to know monitor names before trying it.

## Commands

- `prometheus-lockscreen`
- `prometheus-lockscreen-preview`
- `prometheus-lockctl lock`
- `prometheus-lockctl lock-and-wait`
- `prometheus-lockctl dpms-off-if-locked`
- `prometheus-lockctl dpms-on`
- `prometheus-lockctl sleep-from-lock`
- `prometheus-lockctl power suspend|poweroff|reboot`
- `prometheus-powerctl capabilities --json`
- `prometheus-powerctl run suspend|poweroff|reboot`

## Dependencies

Required:

- Quickshell v0.3.x
- Hyprland
- systemd
- PAM
- `bash`
- `jq`
- `flock` from util-linux
- `busctl` and `timeout` from systemd

Optional:

- `swayidle` for idle locking and suspend automation
- Howdy plus `pam_python3.so` for face unlock

## Safety Defaults

- Face unlock is disabled by default.
- PAM defaults to `/etc/pam.d`; examples are shipped, not installed automatically.
- Power buttons are gated by `WlSessionLock.secure` and by a Hyprland lock-state check in `prometheus-lockctl`.
- Password buffers are cleared on submit, failure, unlock, and power actions.

See [INSTALL.md](INSTALL.md), [SECURITY.md](SECURITY.md), and [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
