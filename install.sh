#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$PROJECT_DIR/common.sh"

DRY_RUN=0
NO_LOGOUT=0
STARTUP_CHOICE='ask'
STARTUP_LEVEL=''
while (( $# )); do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --no-logout) NO_LOGOUT=1; shift ;;
        --startup-on)
            [[ "$STARTUP_CHOICE" != off ]] || fail 'Choose either --startup-on or --startup-off.'
            STARTUP_CHOICE=on; shift ;;
        --startup-off)
            [[ "$STARTUP_CHOICE" != on ]] || fail 'Choose either --startup-on or --startup-off.'
            STARTUP_CHOICE=off; shift ;;
        --startup-level)
            (( $# >= 2 )) || fail '--startup-level requires 1 or 2.'
            [[ "$2" == 1 || "$2" == 2 ]] || fail '--startup-level must be 1 or 2.'
            STARTUP_LEVEL="$2"; shift 2 ;;
        *) fail "Unknown option: $1 (see README.md)" ;;
    esac
done
[[ -z "$STARTUP_LEVEL" || "$STARTUP_CHOICE" != off ]] || fail '--startup-level is incompatible with --startup-off.'
if [[ -n "$STARTUP_LEVEL" && "$STARTUP_CHOICE" == ask ]]; then STARTUP_CHOICE=on; fi

require_user
for cmd in ps qdbus6 kpackagetool6 kwriteconfig6 install grep; do require_command "$cmd"; done
check_platform
check_powerdevil
check_original_not_installed
check_owned_startup_paths

TARGET="$HOME/.local/share/kwin/scripts/$APP_ID"
if [[ -e "$TARGET" && ! -f "$TARGET/metadata.json" ]]; then
    fail "Existing path is not a valid KWin package; refusing overwrite: $TARGET"
fi

# This is an absolute desktop-entry Exec path, never a shell command.
# Reject unusual paths rather than emitting an incorrectly escaped Exec key.
[[ "$STARTUP_HELPER" != *\"* && "$STARTUP_HELPER" != *%* && "$STARTUP_HELPER" != *$'\n'* ]] ||
    fail 'Your home-directory path cannot be safely represented in this autostart entry.'

EXISTING_LEVEL="$(startup_level)"
if [[ -n "$EXISTING_LEVEL" ]]; then CURRENT_STARTUP='on'; else CURRENT_STARTUP='off'; fi

printf '\n%s\n' 'ThinkPad Fullscreen Backlight — MX Linux v0.2'
printf 'KWin package: %s\n' "$APP_ID"
printf '%s\n' 'Fullscreen behavior: preserve your current Plasma keyboard brightness.'
printf 'Startup auto-on currently: %s\n' "$CURRENT_STARTUP"
printf '%s\n' 'Optional startup auto-on runs at KDE login, not before the login screen.'
if (( DRY_RUN )); then
    case "$STARTUP_CHOICE" in
        on) printf '[DRY RUN] Would enable auto-on at level %s.\n' "${STARTUP_LEVEL:-${EXISTING_LEVEL:-2}}" ;;
        off) printf '%s\n' '[DRY RUN] Would disable startup auto-on.' ;;
        ask) printf '%s\n' '[DRY RUN] Would ask whether to turn on the keyboard backlight at KDE login.' ;;
    esac
    printf '%s\n' '[DRY RUN] Would install/upgrade the MX KWin script; no files changed.'
    exit 0
fi

if [[ "$STARTUP_CHOICE" == ask ]]; then
    if [[ "$CURRENT_STARTUP" == on ]]; then
        read -r -p 'Keep keyboard backlight auto-on at each KDE login? [Y/n]: ' answer || answer=''
        case "${answer,,}" in n|no) STARTUP_CHOICE=off;; *) STARTUP_CHOICE=on;; esac
    else
        read -r -p 'Turn keyboard backlight on automatically at each KDE login? [y/N]: ' answer || answer=''
        case "${answer,,}" in y|yes) STARTUP_CHOICE=on;; *) STARTUP_CHOICE=off;; esac
    fi
fi

if [[ "$STARTUP_CHOICE" == on ]]; then
    DEFAULT_LEVEL="${EXISTING_LEVEL:-2}"
    if [[ -z "$STARTUP_LEVEL" ]]; then
        read -r -p "Keyboard backlight startup level (1 or 2) [$DEFAULT_LEVEL]: " answer || answer=''
        STARTUP_LEVEL="${answer:-$DEFAULT_LEVEL}"
    fi
    [[ "$STARTUP_LEVEL" == 1 || "$STARTUP_LEVEL" == 2 ]] || fail 'Invalid startup level; nothing installed.'
fi

# Prepare the desktop file before touching the installed package.
STAGE="$(mktemp -d)"
trap 'rm -rf -- "$STAGE"' EXIT
if [[ "$STARTUP_CHOICE" == on ]]; then
    cat > "$STAGE/autostart.desktop" <<DESKTOP
[Desktop Entry]
# Managed by thinkpad-fullscreen-backlight-mx-sysvinit
Type=Application
Name=ThinkPad Keyboard Backlight (MX)
Comment=Turn on the ThinkPad keyboard backlight at KDE Plasma login
Exec="$STARTUP_HELPER" $STARTUP_LEVEL
OnlyShowIn=KDE;
Terminal=false
X-KDE-autostart-phase=2
DESKTOP
fi

printf '\n%s\n' 'Installing/updating the KWin fullscreen extension...'
if [[ -d "$TARGET" ]]; then
    kpackagetool6 --type=KWin/Script --upgrade "$PROJECT_DIR"
else
    kpackagetool6 --type=KWin/Script --install "$PROJECT_DIR"
fi
kwriteconfig6 --file kwinrc --group Plugins --key "${APP_ID}Enabled" true

# Changes are limited to our owned user-level startup files.
if [[ "$STARTUP_CHOICE" == on ]]; then
    mkdir -p -- "$(dirname -- "$STARTUP_HELPER")" "$(dirname -- "$STARTUP_DESKTOP")"
    install -m 0755 "$PROJECT_DIR/startup/startup-backlight.sh" "$STARTUP_HELPER"
    install -m 0644 "$STAGE/autostart.desktop" "$STARTUP_DESKTOP"
    printf '[OK] Auto-on configured: level %s at each KDE Plasma login.\n' "$STARTUP_LEVEL"
else
    if is_owned_file "$STARTUP_DESKTOP"; then rm -f -- "$STARTUP_DESKTOP"; fi
    if is_owned_file "$STARTUP_HELPER"; then rm -f -- "$STARTUP_HELPER"; fi
    # An opt-out should not retain a misleading status from an earlier login.
    log_dir="${XDG_CACHE_HOME:-$HOME/.cache}/thinkpad-fullscreen-backlight-mx"
    if [[ -f "$log_dir/startup.log" && ! -L "$log_dir/startup.log" ]]; then
        rm -f -- "$log_dir/startup.log"
        rmdir -- "$log_dir" 2>/dev/null || true
    fi
    printf '%s\n' '[OK] Auto-on disabled. The extension will not turn the backlight on at login.'
fi

if ! qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1; then
    printf '%s\n' '[WARN] KWin reconfigure did not reply. Log out and back in.' >&2
fi
printf '%s\n' '[OK] Fullscreen extension installed and enabled.'
printf '%s\n' 'Log out and back in to activate the updated KWin script and test startup auto-on.'
if (( NO_LOGOUT )); then exit 0; fi
read -r -p 'Log out now? [y/N]: ' choice || choice=''
if [[ "${choice,,}" == y || "${choice,,}" == yes ]]; then
    qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout || printf '%s\n' '[WARN] Automatic logout failed; please log out manually.' >&2
fi
