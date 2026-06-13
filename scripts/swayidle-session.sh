#!/usr/bin/env bash

set -euo pipefail

SWAYIDLE="${SWAYIDLE:-swayidle}"
LOCKCTL="${PROMETHEUS_LOCKCTL:-$HOME/.local/bin/prometheus-lockctl}"

if ! command -v "$SWAYIDLE" >/dev/null 2>&1; then
    printf 'swayidle-session: missing swayidle command: %s\n' "$SWAYIDLE" >&2
    exit 127
fi

if [[ ! -x "$LOCKCTL" ]]; then
    printf 'swayidle-session: missing prometheus-lockctl wrapper: %s\n' "$LOCKCTL" >&2
    exit 127
fi

exec "$SWAYIDLE" -w \
    timeout 300 "'$LOCKCTL' dpms-off-if-locked" \
        resume "'$LOCKCTL' dpms-on" \
    timeout 600 "'$LOCKCTL' lock" \
    timeout 900 "'$LOCKCTL' dpms-off-if-locked" \
        resume "'$LOCKCTL' dpms-on" \
    before-sleep "'$LOCKCTL' lock-and-wait" \
    after-resume "'$LOCKCTL' dpms-on" \
    timeout 3600 "'$LOCKCTL' power suspend"
