#!/usr/bin/env bash
# Shared checks: never use sudo and never alter the installed kernel or init system.
set -euo pipefail

APP_ID=thinkpad-fullscreen-backlight-mx-sysvinit
ORIGINAL_ID=thinkpad-fullscreen-backlight
SYSFS=/sys/class/leds/tpacpi::kbd_backlight/brightness
POWERDEVIL=org.kde.Solid.PowerManagement
POWERDEVIL_PATH=/org/kde/Solid/PowerManagement/Actions/KeyboardBrightnessControl
POWERDEVIL_INTERFACE=org.kde.Solid.PowerManagement.Actions.KeyboardBrightnessControl

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_user() { (( EUID != 0 )) || fail 'Run as your normal desktop user, not with sudo.'; }

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1";
}

check_platform() {
    [[ -r /etc/mx-version || -r /etc/mx-release ]] || fail 'MX Linux installation not detected.'
    # MX Linux SysVinit normally exposes init as PID 1.
    local pid1
    pid1="$(ps -p 1 -o comm= | tr -d '[:space:]')"
    [[ "$pid1" == init || "$pid1" == sysvinit ]] || fail "SysVinit required; PID 1 is '$pid1'."
    [[ -r "$SYSFS" ]] || fail "ThinkPad keyboard brightness interface not readable: $SYSFS"
    [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] || fail 'No user session D-Bus address. Run from your KDE desktop session.'
}

powerdevil_get() {
    qdbus6 "$POWERDEVIL" "$POWERDEVIL_PATH" "$POWERDEVIL_INTERFACE.$1"
}

check_powerdevil() {
    local max level
    max="$(powerdevil_get keyboardBrightnessMax 2>/dev/null)" || fail 'PowerDevil keyboard brightness D-Bus interface is unavailable. Nothing has been changed.'
    level="$(powerdevil_get keyboardBrightness 2>/dev/null)" || fail 'Cannot read current keyboard brightness through PowerDevil. Nothing has been changed.'
    [[ "$max" =~ ^[0-9]+$ && "$level" =~ ^[0-9]+$ ]] || fail "PowerDevil returned invalid levels: current='$level', max='$max'."
    [[ "$max" == 2 && "$level" -le 2 ]] || fail "Unsupported brightness range: current=$level max=$max (T590 expected 0..2)."
    printf 'PowerDevil keyboard brightness: %s/2 (read-only probe OK)\n' "$level"
}

check_original_not_installed() {
    local original="$HOME/.local/share/kwin/scripts/$ORIGINAL_ID"
    [[ ! -e "$original" ]] || fail "The original KDE edition exists at $original. Uninstall it before installing this separate MX port."
}

# The MX edition owns only these two user-level login files.
STARTUP_DESKTOP="$HOME/.config/autostart/thinkpad-fullscreen-backlight-mx.desktop"
STARTUP_HELPER="$HOME/.local/libexec/thinkpad-fullscreen-backlight-mx/startup-backlight.sh"
OWNERSHIP_MARKER='# Managed by thinkpad-fullscreen-backlight-mx-sysvinit'

is_owned_file() {
    local filename="$1"
    [[ -f "$filename" && ! -L "$filename" ]] && grep -Fxq -- "$OWNERSHIP_MARKER" "$filename"
}

check_owned_startup_paths() {
    local filename
    for filename in "$STARTUP_DESKTOP" "$STARTUP_HELPER"; do
        if [[ -e "$filename" || -L "$filename" ]] && ! is_owned_file "$filename"; then
            fail "Refusing to overwrite a startup file not owned by this tool: $filename"
        fi
    done
}

startup_installed() {
    is_owned_file "$STARTUP_DESKTOP" && is_owned_file "$STARTUP_HELPER"
}

startup_level() {
    if startup_installed; then
        sed -n -E 's/^Exec=.* ([12])$/\1/p' "$STARTUP_DESKTOP" | head -n 1
    fi
}
