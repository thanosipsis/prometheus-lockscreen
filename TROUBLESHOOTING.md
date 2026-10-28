# Troubleshooting

## Preview

```sh
prometheus-lockscreen-preview
```

Preview mode is not a real lock. Use it for layout and config checks.

## Multi-Monitor

Default:

```conf
target_screen=
```

This shows the UI on every monitor. To show the UI on one monitor, get names with:

```sh
hyprctl monitors
```

Then set:

```conf
target_screen=MONITOR_NAME
```

All monitors remain covered either way.

## Face Unlock Does Nothing

Face unlock is disabled by default. Check:

```sh
rg '^face_auth=' ~/.config/quickshell/prometheus-lockscreen/features.conf
test -r /usr/lib/security/howdy/pam.py
test -r /usr/lib/security/pam_python3.so -o -x /usr/lib/security/pam_python3.so
test -r /etc/pam.d/prometheus-lockscreen-face
```

## Frozen Lock Screen After Resume

If the whole display freezes after waking, check the compositor and graphics
driver before assuming password focus is broken:

```sh
journalctl -b -1 -k
ls ~/.cache/hyprland/hyprlandCrashReport*.txt
```

An NVIDIA/Hyprland setup was observed freezing and crashing after resume with
`format XR30 isn't supported by primary backend` and a failed swapchain buffer
allocation. Setting **all connected outputs** to `bitdepth = 8` in the active
Hyprland monitor rules resolved the freeze in that setup. This is a graphics
workaround, not a universal fix; save the original rules before trying it.
Keep resolution and refresh rate unchanged initially, reload Hyprland, and
check `hyprctl monitors -j` for an 8-bit format such as `XRGB8888`.

## Known qmllint Warnings

`qmllint` should exit successfully. Expected warnings:

- `PanelWindow is not creatable`: Quickshell runtime type metadata is not fully represented to Qt's linter.
- `Quick.layout-positioning` on footer transforms: burn-in protection intentionally shifts footer rows.

## Uninstall

```sh
systemctl --user disable --now swayidle.service
rm -f ~/.config/systemd/user/swayidle.service
rm -f ~/.local/bin/prometheus-lockscreen ~/.local/bin/prometheus-lockscreen-preview ~/.local/bin/prometheus-lockctl
rm -rf ~/.config/quickshell/prometheus-lockscreen ~/.local/share/prometheus-lockscreen
sudo rm -f /etc/pam.d/prometheus-lockscreen /etc/pam.d/prometheus-lockscreen-face
systemctl --user daemon-reload
```

