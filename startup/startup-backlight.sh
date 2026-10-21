#!/usr/bin/env bash
# Managed by thinkpad-fullscreen-backlight-mx-sysvinit
# One-shot KDE Plasma login helper. No resident daemon and no elevated privileges.
set -uo pipefail

TARGET="${1:-}"
if [[ "$TARGET" != 1 && "$TARGET" != 2 ]]; then
    printf '%s\n' 'Usage: startup-backlight.sh <1|2>' >&2
    exit 2
fi

POWERDEVIL='org.kde.Solid.PowerManagement'
OBJECT='/org/kde/Solid/PowerManagement/Actions/KeyboardBrightnessControl'
INTERFACE='org.kde.Solid.PowerManagement.Actions.KeyboardBrightnessControl'
SYSFS='/sys/class/leds/tpacpi::kbd_backlight/brightness'
MAX_RETRIES=30
DELAY=1

# Test-only injection: never activates outside the explicit test mode.
if [[ "${BACKLIGHT_TEST_MODE:-}" == 1 ]]; then
    SYSFS="${BACKLIGHT_TEST_SYSFS:?test sysfs is required}"
    MAX_RETRIES="${BACKLIGHT_TEST_RETRIES:-3}"
    DELAY=0
fi

LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/thinkpad-fullscreen-backlight-mx"
LOG_FILE="$LOG_DIR/startup.log"
umask 077
mkdir -p -- "$LOG_DIR" || exit 1
# Keep only the most recent startup result. No unbounded logs.
: > "$LOG_FILE"
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"; }

if [[ ! -r "$SYSFS" ]]; then
    log 'FAILED: ThinkPad keyboard brightness interface not found.'
    exit 1
fi
if ! command -v qdbus6 >/dev/null 2>&1; then
    log 'FAILED: qdbus6 command not found.'
    exit 1
fi

for ((attempt=1; attempt<=MAX_RETRIES; attempt++)); do
    max="$(qdbus6 "$POWERDEVIL" "$OBJECT" "$INTERFACE.keyboardBrightnessMax" 2>/dev/null)" &&
    current="$(qdbus6 "$POWERDEVIL" "$OBJECT" "$INTERFACE.keyboardBrightness" 2>/dev/null)" || {
        sleep "$DELAY"
        continue
    }
    if [[ "$max" != 2 || ! "$current" =~ ^[012]$ ]]; then
        log "FAILED: Unexpected PowerDevil brightness range/current reading: max=$max current=$current"
        exit 1
    fi
    if [[ "$current" == "$TARGET" ]]; then
        log "OK: Keyboard backlight already at level $TARGET."
        exit 0
    fi
    if ! qdbus6 "$POWERDEVIL" "$OBJECT" "$INTERFACE.setKeyboardBrightnessSilent" "$TARGET" >/dev/null 2>&1; then
        sleep "$DELAY"
        continue
    fi
    # Verify PowerDevil applied the requested value. This checks the actual API.
    for check in 1 2 3; do
        actual="$(qdbus6 "$POWERDEVIL" "$OBJECT" "$INTERFACE.keyboardBrightness" 2>/dev/null)" || actual=''
        if [[ "$actual" == "$TARGET" ]]; then
            log "OK: Set keyboard backlight to level $TARGET at KDE login."
            exit 0
        fi
        sleep "$DELAY"
    done
    log "FAILED: PowerDevil accepted request but did not confirm level $TARGET (last=$actual)."
    exit 1
done
log "FAILED: PowerDevil keyboard brightness unavailable after $MAX_RETRIES attempts."
exit 1
