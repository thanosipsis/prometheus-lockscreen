# Install

These instructions are for a source install on an Arch/CachyOS-style Hyprland session.

## Human Install

From this repository:

```sh
install -Dm755 bin/prometheus-lockscreen ~/.local/bin/prometheus-lockscreen
install -Dm755 bin/prometheus-lockscreen-preview ~/.local/bin/prometheus-lockscreen-preview
install -Dm755 bin/prometheus-lockctl ~/.local/bin/prometheus-lockctl

mkdir -p ~/.config/quickshell
cp -R configs/prometheus-lockscreen ~/.config/quickshell/

install -Dm755 scripts/resume-displays.sh ~/.local/share/prometheus-lockscreen/scripts/resume-displays.sh
install -Dm755 scripts/swayidle-session.sh ~/.local/share/prometheus-lockscreen/scripts/swayidle-session.sh

cp ~/.config/quickshell/prometheus-lockscreen/features.conf.example \
  ~/.config/quickshell/prometheus-lockscreen/features.conf
```

Install the PAM service only after reviewing it:

```sh
sudo install -Dm644 examples/pam/prometheus-lockscreen.arch.example /etc/pam.d/prometheus-lockscreen
```

Optional face auth:

```sh
sudo install -Dm644 examples/pam/prometheus-lockscreen-face.howdy.example /etc/pam.d/prometheus-lockscreen-face
```

Then set `face_auth=1` in `~/.config/quickshell/prometheus-lockscreen/features.conf` only after confirming Howdy and `pam_python3.so` work on your system.

Optional swayidle unit:

```sh
install -Dm644 examples/systemd/user/swayidle.service ~/.config/systemd/user/swayidle.service
systemctl --user daemon-reload
systemctl --user enable --now swayidle.service
```

Example Hyprland bind:

```conf
bind = SUPER, L, exec, prometheus-lockctl lock
```

## Agent Install

Agents should follow this order:

1. Run static checks before installing:

   ```sh
   bash -n bin/prometheus-lockscreen bin/prometheus-lockscreen-preview bin/prometheus-lockctl scripts/*.sh
   /usr/lib/qt6/bin/qmllint configs/prometheus-lockscreen/shell.qml
   rg "LOCAL_HOME|LOCAL_USER|LOCAL_MONITOR|browser_specific_cleanup|vendored_dependency_dir" .
   ```

2. Copy user files only; do not modify PAM yet.
3. Run `prometheus-lockscreen-preview`.
4. Ask the human to review the PAM example before any `sudo install` into `/etc/pam.d`.
5. Test dry-run power actions:

   ```sh
   PROMETHEUS_LOCKCTL_DRY_RUN=1 PROMETHEUS_LOCKCTL_ASSUME_LOCKED=1 prometheus-lockctl power suspend
   ```

6. Enable systemd user units only after preview and PAM review pass.

Agents must not enable face auth by default.

