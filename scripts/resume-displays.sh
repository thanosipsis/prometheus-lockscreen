#!/usr/bin/env bash

set -u

HYPRCTL="${HYPRCTL:-hyprctl}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
LOG_DIR="${PROMETHEUS_RESUME_LOG_DIR:-$CACHE_HOME}"
LOG_FILE="$LOG_DIR/hyprland-resume-displays.log"
LOCK_FILE="$LOG_DIR/hyprland-resume-displays.lock"

mkdir -p "$LOG_DIR"
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

{
    printf '\n[%s] resume display recovery start\n' "$(date --iso-8601=seconds)"

    if ! command -v "$HYPRCTL" >/dev/null 2>&1; then
        printf '[%s] missing hyprctl command: %s\n' "$(date --iso-8601=seconds)" "$HYPRCTL"
        exit 127
    fi

    for delay in 0 0.5 1 2 4; do
        sleep "$delay"
        printf '[%s] dpms enable after %ss\n' "$(date --iso-8601=seconds)" "$delay"
        "$HYPRCTL" dispatch 'hl.dsp.dpms({ action = "enable" })'
    done

    printf '[%s] monitor state after recovery\n' "$(date --iso-8601=seconds)"
    "$HYPRCTL" monitors -j
    printf '[%s] resume display recovery end\n' "$(date --iso-8601=seconds)"
} >>"$LOG_FILE" 2>&1
