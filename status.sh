#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$PROJECT_DIR/common.sh"
require_user
printf '%s\n' 'ThinkPad Fullscreen Backlight — MX Linux v0.2 (read-only status)'
printf 'PID 1: %s\n' "$(ps -p 1 -o comm= | xargs)"
if [[ -r /etc/mx-version ]]; then printf 'MX: %s\n' "$(head -n 1 /etc/mx-version)"; fi
PACKAGE="$HOME/.local/share/kwin/scripts/$APP_ID"
if [[ -d "$PACKAGE" ]]; then printf 'KWin package: installed (%s)\n' "$PACKAGE"; else printf '%s\n' 'KWin package: not found'; fi
if command -v kreadconfig6 >/dev/null 2>&1; then
    printf 'KWin enabled: %s\n' "$(kreadconfig6 --file kwinrc --group Plugins --key "${APP_ID}Enabled" --default false)"
else
    printf '%s\n' 'KWin enabled: unknown (kreadconfig6 not found)'
fi
if startup_installed; then
    printf 'KDE login auto-on: enabled (level %s)\n' "$(startup_level)"
elif [[ -e "$STARTUP_DESKTOP" || -e "$STARTUP_HELPER" ]]; then
    printf '%s\n' 'KDE login auto-on: incomplete/needs inspection'
else
    printf '%s\n' 'KDE login auto-on: disabled (leave brightness unchanged)'
fi
LOG_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/thinkpad-fullscreen-backlight-mx/startup.log"
if [[ -r "$LOG_FILE" ]]; then
    printf 'Last login auto-on attempt: %s\n' "$(tail -n 1 "$LOG_FILE")"
fi
if command -v qdbus6 >/dev/null 2>&1 && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    powerdevil_get keyboardBrightnessMax 2>/dev/null | sed 's/^/PowerDevil max: /' || printf '%s\n' 'PowerDevil max: unavailable'
    powerdevil_get keyboardBrightness 2>/dev/null | sed 's/^/PowerDevil current: /' || printf '%s\n' 'PowerDevil current: unavailable'
else
    printf '%s\n' 'PowerDevil: unavailable (no session bus or qdbus6)'
fi
