#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$PROJECT_DIR/common.sh"
DRY_RUN=0
NO_LOGOUT=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --no-logout) NO_LOGOUT=1 ;;
        *) fail "Unknown option: $arg (supported: --dry-run, --no-logout)" ;;
    esac
done
require_user
for cmd in kpackagetool6 kwriteconfig6 grep; do require_command "$cmd"; done
check_owned_startup_paths
printf 'Remove MX KWin package: %s\n' "$APP_ID"
printf '%s\n' 'Also remove only the auto-on helper and desktop entry installed by this tool.'
printf '%s\n' 'No system packages, other KWin scripts, or keyboard brightness settings will be changed.'
if (( DRY_RUN )); then
    [[ -e "$STARTUP_DESKTOP" ]] && printf '[DRY RUN] Remove %s\n' "$STARTUP_DESKTOP"
    [[ -e "$STARTUP_HELPER" ]] && printf '[DRY RUN] Remove %s\n' "$STARTUP_HELPER"
    printf '%s\n' '[DRY RUN] No changes made.'
    exit 0
fi

kwriteconfig6 --file kwinrc --group Plugins --key "${APP_ID}Enabled" false
if [[ -d "$HOME/.local/share/kwin/scripts/$APP_ID" ]]; then
    kpackagetool6 --type=KWin/Script --remove "$APP_ID"
else
    printf '%s\n' 'KWin package already absent.'
fi
if is_owned_file "$STARTUP_DESKTOP"; then rm -f -- "$STARTUP_DESKTOP"; fi
if is_owned_file "$STARTUP_HELPER"; then rm -f -- "$STARTUP_HELPER"; fi
LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/thinkpad-fullscreen-backlight-mx"
if [[ -f "$LOG_DIR/startup.log" && ! -L "$LOG_DIR/startup.log" ]]; then
    rm -f -- "$LOG_DIR/startup.log"
    rmdir -- "$LOG_DIR" 2>/dev/null || true
fi
if command -v qdbus6 >/dev/null 2>&1; then
    qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$APP_ID" >/dev/null 2>&1 || true
    qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
fi
printf '%s\n' '[OK] MX extension and its owned auto-on files removed.'
printf '%s\n' 'Log out and back in to ensure the old KWin script is unloaded.'
if (( NO_LOGOUT )); then exit 0; fi
read -r -p 'Log out now? [y/N]: ' choice || choice=''
if [[ "${choice,,}" == y || "${choice,,}" == yes ]]; then
    qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout || printf '%s\n' '[WARN] Automatic logout failed; please log out manually.' >&2
fi
