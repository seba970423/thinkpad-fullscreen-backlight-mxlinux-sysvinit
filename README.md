# ThinkPad Fullscreen Keyboard Backlight — MX Linux (SysVinit / Plasma 6)

**v0.2 test build.** Based on the ThinkPad Fullscreen Backlight KDE6 project, this is a **separate MX Linux edition**, with its own KWin package ID. The original repository and installation are left untouched.

Here's the link for the systemd variant: https://github.com/seba970423/thinkpad-fullscreen-backlight-kde6

## Features

- Turns off the ThinkPad keyboard backlight when a regular window enters fullscreen.
- Restores the level that was active before fullscreen (off, 1, or 2).
- Respects nonzero manual keyboard brightness changes made during fullscreen.
- Reacts to KWin window events; no background polling.
- Optional **auto-on at KDE login**, chosen explicitly during installation. Default: **No**.
- If auto-on is enabled, prompts for startup brightness level **1** or **2** (default 2). The chosen level is applied at each new KDE Plasma login, even if the keyboard starts off.
- Includes read-only status, dry-run and complete uninstall scripts.
- No privileged helper or administrator password needed.

**Important distinction:** Automatic startup runs when the user signs in to **KDE Plasma**, not at the firmware/BIOS boot screen or greeter. This follows KDE's XDG Autostart mechanism, which does not require modifying the init system. If you choose **No**, the extension leaves login brightness unchanged; MX Linux or Plasma may still apply their own backlight policy. You can manually enable the keyboard light using the ThinkPad shortcut.

## Requirements

- Installed MX Linux 25.x, SysVinit, KDE Plasma 6/KWin (Wayland), normal user login session.
- ThinkPad keyboard-backlight interface `/sys/class/leds/tpacpi::kbd_backlight/brightness` and PowerDevil keyboard brightness interface with levels 0–2.
- `qdbus6`, `kpackagetool6`, `kwriteconfig6`.

## Installation / upgrade

Run **as a normal desktop user**, not with `sudo`:

```bash
git clone https://github.com/seba970423/thinkpad-fullscreen-backlight-mxlinux-sysvinit
cd thinkpad-fullscreen-backlight-mxlinux-sysvinit
./install.sh --dry-run
./install.sh
./status.sh
```

Installation asks:

```text
Turn keyboard backlight on automatically at each KDE login? [y/N]:
```

When the answer is `y`, it then asks for startup level `1` or `2`. When the answer is `n` or Enter, no login auto-on is configured. During an upgrade of an existing auto-on installation, pressing Enter **preserves** the enabled setting and its level unless you change them.

For automation or an explicit test:

```bash
git clone https://github.com/seba970423/thinkpad-fullscreen-backlight-mxlinux-sysvinit
cd thinkpad-fullscreen-backlight-mxlinux-sysvinit
./install.sh --startup-on --startup-level 1 --no-logout
./install.sh --startup-on --startup-level 2 --no-logout
./install.sh --startup-off --no-logout
./install.sh --dry-run --startup-on --startup-level 2
```

A logout/login is recommended after upgrading so KWin reloads the script and the XDG Autostart entry can execute. The installer offers an optional logout prompt, default **No**.

### What auto-on installs

With explicit opt-in only:

- `$HOME/.config/autostart/thinkpad-fullscreen-backlight-mx.desktop`
- `$HOME/.local/libexec/thinkpad-fullscreen-backlight-mx/startup-backlight.sh`

The helper waits up to about 30 seconds for PowerDevil at login, verifies the requested brightness level (1 or 2), writes a one-run diagnostic to `$HOME/.cache/thinkpad-fullscreen-backlight-mx/startup.log`, then exits. It is **not a service**, doesn't poll continuously, and doesn't set any system-wide startup policy.

If you choose No, existing tool-owned auto-on files are removed, but the fullscreen extension remains installed. There is no forced-off behavior at login.

## Behavior during fullscreen

- Level 2 → fullscreen 0 → exit restores 2.
- Level 1 → fullscreen 0 → exit restores 1.
- Level 0 → fullscreen stays at 0 → exit stays at 0.
- Manually switch to level 1 while fullscreen → exit leaves it at 1.
- Multiple fullscreen windows count as one continuous session.

**Known limitation:** If the user manually turns the light on and then returns it to 0 before leaving fullscreen, the current KWin D-Bus approach cannot reliably distinguish that final manual 0 from our own automatic 0. The original level may be restored. Auto-on at login does not alter this fullscreen limitation.

## Status and uninstall

```bash
./status.sh
./uninstall.sh --dry-run
./uninstall.sh
```

The status command reports whether login auto-on is configured, the selected level, the most recent startup result, and the current PowerDevil brightness.

The uninstaller disables and removes only this MX KWin script, its **owned** auto-on files, and its small startup log. It does not uninstall KDE, alter other extensions, or change your current keyboard brightness. Existing unknown files at the tool's paths are never overwritten or removed. A logout/login ensures KWin drops any previously loaded script.

## Validation checklist

1. Test fullscreen entry/exit at levels 0, 1, and 2.
2. Test manually turning the backlight on while fullscreen.
3. Install with `n`; log out/in and confirm this extension **does not** force a login brightness.
4. Reinstall with `y` and level 1; log out/in and verify auto-on 1 in `./status.sh`.
5. Reinstall with `y` and level 2; log out/in and verify auto-on 2.
6. Uninstall, log out/in, and verify the KWin package and owned autostart files are gone.

## License

MIT (see LICENSE). This MX edition is separate from the original KDE6 project.
