# Security

This project includes a real session lock and PAM authentication. Treat configuration changes carefully.

## Session Lock

- The lockscreen uses `WlSessionLock`, not a regular layer-shell window.
- Every monitor must be covered.
- `target_screen` only changes where the interactive UI appears; it must not change monitor coverage.
- Power actions require `WlSessionLock.secure` and the controller's Hyprland lock-state check.

## PAM

PAM is distro-specific. The shipped files are examples for Arch/CachyOS-style systems.

Before installing PAM files:

- Keep a TTY or SSH recovery path available.
- Confirm the distro uses `system-auth`.
- Review Howdy and `pam_python3.so` paths before enabling face auth.
- Test preview mode before triggering a real lock.

Recovery:

```sh
sudo rm -f /etc/pam.d/prometheus-lockscreen /etc/pam.d/prometheus-lockscreen-face
```

Then set `face_auth=0` in the lockscreen config.

## Power Buttons

`prometheus-lockctl power suspend|poweroff|reboot` refuses real actions unless the session is locked. Use dry-run mode when auditing:

```sh
PROMETHEUS_LOCKCTL_DRY_RUN=1 PROMETHEUS_LOCKCTL_ASSUME_LOCKED=1 prometheus-lockctl power suspend
```

The controller delegates to `prometheus-powerctl`, which checks the matching
systemd-logind capability and only accepts the action when logind reports
`yes`. It calls the login1 D-Bus method directly and uses command fallbacks
only when login1 is unavailable before dispatch.
