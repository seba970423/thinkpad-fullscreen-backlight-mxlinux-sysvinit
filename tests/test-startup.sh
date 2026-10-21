#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP="$(mktemp -d)"
trap 'rm -rf -- "$TEMP"' EXIT
mkdir -p "$TEMP/bin" "$TEMP/home"
: > "$TEMP/sysfs"
cat > "$TEMP/bin/qdbus6" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "${3:-}" in
    *.keyboardBrightnessMax)
        echo "$(cat "$MOCK_DATA/max")" ;;
    *.keyboardBrightness)
        count=$(cat "$MOCK_DATA/unavailable")
        if [[ "$count" -gt 0 ]]; then
            printf '%s\n' "$((count-1))" > "$MOCK_DATA/unavailable"
            exit 1
        fi
        cat "$MOCK_DATA/current" ;;
    *.setKeyboardBrightnessSilent)
        echo "$4" > "$MOCK_DATA/current" ;;
    *) exit 0 ;;
esac
MOCK
chmod +x "$TEMP/bin/qdbus6"
echo 2 > "$TEMP/max"
echo 0 > "$TEMP/current"
echo 0 > "$TEMP/unavailable"
export HOME="$TEMP/home" MOCK_DATA="$TEMP" PATH="$TEMP/bin:$PATH"
export BACKLIGHT_TEST_MODE=1 BACKLIGHT_TEST_SYSFS="$TEMP/sysfs" BACKLIGHT_TEST_RETRIES=5
"$ROOT/startup/startup-backlight.sh" 2
[[ "$(cat "$TEMP/current")" == 2 ]]
grep -q 'OK: Set keyboard backlight to level 2' "$HOME/.cache/thinkpad-fullscreen-backlight-mx/startup.log"
echo 1 > "$TEMP/current"
echo 2 > "$TEMP/unavailable"
"$ROOT/startup/startup-backlight.sh" 2
[[ "$(cat "$TEMP/current")" == 2 ]]
"$ROOT/startup/startup-backlight.sh" 2
grep -q 'already at level 2' "$HOME/.cache/thinkpad-fullscreen-backlight-mx/startup.log"
echo 4 > "$TEMP/max"
if "$ROOT/startup/startup-backlight.sh" 1; then echo 'Unexpected success with invalid range' >&2; exit 1; fi
grep -q 'FAILED: Unexpected PowerDevil brightness range' "$HOME/.cache/thinkpad-fullscreen-backlight-mx/startup.log"
echo 2 > "$TEMP/max"
if "$ROOT/startup/startup-backlight.sh" 0 >/dev/null 2>&1; then echo 'Unexpected success with invalid target' >&2; exit 1; fi

# Test installer, dry-run, opt-in, level change, opt-out, uninstall with an isolated HOME.
cp -a "$ROOT" "$TEMP/project"
cat >> "$TEMP/project/common.sh" <<'MOCK_OVERRIDE'
check_platform() { :; }
check_powerdevil() { :; }
MOCK_OVERRIDE
cat > "$TEMP/bin/kpackagetool6" <<'MOCK_PACKAGE'
#!/usr/bin/env bash
set -euo pipefail
if [[ " $* " == *' --remove '* ]]; then
    rm -rf "$HOME/.local/share/kwin/scripts/thinkpad-fullscreen-backlight-mx-sysvinit"
else
    dest="$HOME/.local/share/kwin/scripts/thinkpad-fullscreen-backlight-mx-sysvinit"
    mkdir -p "$dest"
    cp "$MOCK_PROJECT/metadata.json" "$dest/metadata.json"
fi
MOCK_PACKAGE
cat > "$TEMP/bin/kwriteconfig6" <<'MOCK_CONFIG'
#!/usr/bin/env bash
exit 0
MOCK_CONFIG
chmod +x "$TEMP/bin/kpackagetool6" "$TEMP/bin/kwriteconfig6"
export MOCK_PROJECT="$TEMP/project"
"$MOCK_PROJECT/install.sh" --dry-run --startup-on --startup-level 1 >/dev/null
[[ ! -e "$HOME/.config/autostart/thinkpad-fullscreen-backlight-mx.desktop" ]]
"$MOCK_PROJECT/install.sh" --startup-on --startup-level 1 --no-logout >/dev/null
[[ "$(cat "$HOME/.config/autostart/thinkpad-fullscreen-backlight-mx.desktop" | grep '^Exec=')" == *' 1' ]]
"$MOCK_PROJECT/install.sh" --startup-on --startup-level 2 --no-logout >/dev/null
[[ "$(cat "$HOME/.config/autostart/thinkpad-fullscreen-backlight-mx.desktop" | grep '^Exec=')" == *' 2' ]]
"$MOCK_PROJECT/install.sh" --startup-off --no-logout >/dev/null
[[ ! -e "$HOME/.config/autostart/thinkpad-fullscreen-backlight-mx.desktop" ]]
[[ ! -e "$HOME/.local/libexec/thinkpad-fullscreen-backlight-mx/startup-backlight.sh" ]]
"$MOCK_PROJECT/install.sh" --startup-on --startup-level 1 --no-logout >/dev/null
"$MOCK_PROJECT/uninstall.sh" --dry-run >/dev/null
[[ -e "$HOME/.config/autostart/thinkpad-fullscreen-backlight-mx.desktop" ]]
"$MOCK_PROJECT/uninstall.sh" --no-logout >/dev/null
[[ ! -e "$HOME/.config/autostart/thinkpad-fullscreen-backlight-mx.desktop" ]]
[[ ! -d "$HOME/.local/share/kwin/scripts/thinkpad-fullscreen-backlight-mx-sysvinit" ]]
# Reject user-owned files at reserved paths.
mkdir -p "$HOME/.config/autostart"
echo '# not our tool' > "$HOME/.config/autostart/thinkpad-fullscreen-backlight-mx.desktop"
if "$MOCK_PROJECT/install.sh" --startup-on --startup-level 2 --no-logout >/dev/null 2>&1; then
    echo 'Unexpected overwrite of a foreign autostart entry' >&2
    exit 1
fi
[[ "$(cat "$HOME/.config/autostart/thinkpad-fullscreen-backlight-mx.desktop")" == '# not our tool' ]]
printf '%s\n' 'PASS: auto-on helper, transient D-Bus failures, ownership, opt-in/opt-out and uninstall.'
