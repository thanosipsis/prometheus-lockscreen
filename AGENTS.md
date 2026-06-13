# Agent Instructions

This repo is only tested on Arch/CachyOS-style Hyprland sessions.

## Install Order

1. Run syntax and lint checks:

   ```sh
   bash -n bin/prometheus-lockscreen bin/prometheus-lockscreen-preview bin/prometheus-lockctl scripts/*.sh
   /usr/lib/qt6/bin/qmllint configs/prometheus-lockscreen/shell.qml
   ```

2. Install user files to `~/.local/bin`, `~/.config/quickshell/prometheus-lockscreen`, and `~/.local/share/prometheus-lockscreen`.
3. Copy `features.conf.example` to `features.conf`.
4. Keep `face_auth=0` unless the human explicitly asks for face auth and confirms PAM review.
5. Do not install files into `/etc/pam.d` without explicit human confirmation.
6. Verify `prometheus-lockscreen-preview`.
7. Test power actions with dry-run env before any real lockscreen power testing.

## Boundaries

- Do not treat PAM examples as universal.
- Do not publish local screenshots, usernames, monitor names, or logs.
- Do not replace an existing lockscreen without creating a recovery path.

