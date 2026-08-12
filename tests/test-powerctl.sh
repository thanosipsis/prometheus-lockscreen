#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POWERCTL="$REPO_ROOT/bin/prometheus-powerctl"
LOCKCTL="$REPO_ROOT/bin/prometheus-lockctl"
TEST_DIR="$(mktemp -d /tmp/prometheus-powerctl-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

mkdir -p "$TEST_DIR/bin" "$TEST_DIR/logs"

cat >"$TEST_DIR/bin/busctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FAKE_CALLS"
method=""
for arg in "$@"; do
    case "$arg" in
        CanSuspend|CanReboot|CanPowerOff|Suspend|Reboot|PowerOff) method="$arg" ;;
    esac
done
case "$method" in
    CanSuspend) state="${FAKE_SUSPEND_STATE:-yes}" ;;
    CanReboot) state="${FAKE_REBOOT_STATE:-yes}" ;;
    CanPowerOff) state="${FAKE_POWEROFF_STATE:-yes}" ;;
    Suspend|Reboot|PowerOff)
        exit "${FAKE_DISPATCH_STATUS:-0}"
        ;;
    *) exit 64 ;;
esac
[[ "$state" != "unavailable" ]] || exit 1
printf 's "%s"\n' "$state"
EOF

cat >"$TEST_DIR/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >>"$FAKE_CALLS"
exit "${FAKE_SYSTEMCTL_STATUS:-0}"
EOF

cat >"$TEST_DIR/bin/loginctl" <<'EOF'
#!/usr/bin/env bash
printf 'loginctl %s\n' "$*" >>"$FAKE_CALLS"
exit "${FAKE_LOGINCTL_STATUS:-0}"
EOF

cat >"$TEST_DIR/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '[{"solitaryBlockedBy":["LOCK"]}]'
EOF

cat >"$TEST_DIR/bin/powerctl-fail" <<'EOF'
#!/usr/bin/env bash
exit 42
EOF

chmod +x "$TEST_DIR/bin/"*
export PATH="$TEST_DIR/bin:$PATH"
export FAKE_CALLS="$TEST_DIR/calls.log"
export PROMETHEUS_POWERCTL_BUSCTL="$TEST_DIR/bin/busctl"
export PROMETHEUS_POWERCTL_SYSTEMCTL="$TEST_DIR/bin/systemctl"
export PROMETHEUS_POWERCTL_LOGINCTL="$TEST_DIR/bin/loginctl"
export PROMETHEUS_POWERCTL_LOG_DIR="$TEST_DIR/logs"
export PROMETHEUS_POWERCTL_LOCK_FILE="$TEST_DIR/power.lock"
export PROMETHEUS_LOCKCTL_LOG_DIR="$TEST_DIR/logs"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_contains() {
    local haystack="$1" needle="$2"
    [[ "$haystack" == *"$needle"* ]] || fail "expected '$needle' in '$haystack'"
}

capabilities="$(FAKE_SUSPEND_STATE=yes FAKE_REBOOT_STATE=no FAKE_POWEROFF_STATE=challenge \
    "$POWERCTL" capabilities --json)"
assert_contains "$capabilities" '"suspend":{"state":"yes","available":true}'
assert_contains "$capabilities" '"reboot":{"state":"no","available":false}'
assert_contains "$capabilities" '"poweroff":{"state":"challenge","available":false}'

capabilities="$(FAKE_SUSPEND_STATE=unavailable "$POWERCTL" capabilities --json)"
assert_contains "$capabilities" '"suspend":{"state":"unavailable","available":false}'

: >"$FAKE_CALLS"
for action in suspend reboot poweroff; do
    "$POWERCTL" run "$action"
done
calls="$(<"$FAKE_CALLS")"
assert_contains "$calls" 'Suspend b true'
assert_contains "$calls" 'Reboot b true'
assert_contains "$calls" 'PowerOff b true'

: >"$FAKE_CALLS"
if FAKE_DISPATCH_STATUS=19 "$POWERCTL" run suspend; then
    fail "failed D-Bus dispatch returned success"
else
    [[ $? -eq 19 ]] || fail "failed D-Bus dispatch did not preserve exit 19"
fi
[[ "$(<"$FAKE_CALLS")" != *"systemctl suspend"* ]] || fail "dispatch failure incorrectly used fallback"
[[ "$(<"$FAKE_CALLS")" != *"loginctl suspend"* ]] || fail "dispatch failure incorrectly used fallback"

: >"$FAKE_CALLS"
FAKE_SUSPEND_STATE=unavailable "$POWERCTL" run suspend
assert_contains "$(<"$FAKE_CALLS")" 'systemctl suspend'

flock "$TEST_DIR/power.lock" sleep 2 &
holder=$!
sleep 0.1
if "$POWERCTL" run reboot; then
    fail "duplicate power action was accepted"
else
    [[ $? -eq 75 ]] || fail "duplicate power action did not return 75"
fi
wait "$holder"

if HYPRCTL="$TEST_DIR/bin/hyprctl" PROMETHEUS_POWERCTL="$TEST_DIR/bin/powerctl-fail" \
    "$LOCKCTL" power suspend; then
    fail "prometheus-lockctl hid backend failure"
else
    [[ $? -eq 42 ]] || fail "prometheus-lockctl did not preserve backend exit 42"
fi

printf 'PASS: prometheus power action regression tests\n'
