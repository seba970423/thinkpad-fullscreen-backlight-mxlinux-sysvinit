// ThinkPad Fullscreen Backlight — MX Linux / SysVinit edition.
// Uses PowerDevil to control keyboard brightness within the KDE session.
const POWERDEVIL_SERVICE = "org.kde.Solid.PowerManagement";
const KEYBOARD_PATH = "/org/kde/Solid/PowerManagement/Actions/KeyboardBrightnessControl";
const KEYBOARD_INTERFACE = "org.kde.Solid.PowerManagement.Actions.KeyboardBrightnessControl";

// idle -> measuring -> fullscreen -> restoring -> idle
let phase = "idle";
let savedLevel = null;
let requestGeneration = 0;

function fullscreenExists() {
    const windows = workspace.stackingOrder;
    for (let i = 0; i < windows.length; ++i) {
        const window = windows[i];
        if (window && window.fullScreen && !window.minimized && !window.specialWindow) {
            return true;
        }
    }
    return false;
}

function readKeyboardLevel(callback) {
    callDBus(POWERDEVIL_SERVICE, KEYBOARD_PATH, KEYBOARD_INTERFACE,
        "keyboardBrightness", function (level) {
            if (typeof level !== "number" || !Number.isInteger(level) || level < 0 || level > 2) {
                print("ThinkPad fullscreen backlight: unsupported keyboard brightness reading: " + String(level));
                callback(null);
                return;
            }
            callback(level);
        });
}

function setKeyboardLevel(level) {
    // KWin's callDBus is asynchronous. PowerDevil owns the brightness policy,
    // so this does not require a privileged helper and does not create an OSD.
    callDBus(POWERDEVIL_SERVICE, KEYBOARD_PATH, KEYBOARD_INTERFACE,
        "setKeyboardBrightnessSilent", level);
}

function updateBacklight() {
    const isFullscreen = fullscreenExists();

    // A window left fullscreen before the initial D-Bus reply arrived.
    if (!isFullscreen && phase === "measuring") {
        ++requestGeneration; // Invalidate the pending read callback.
        phase = "idle";
        return;
    }

    if (isFullscreen && phase === "idle") {
        phase = "measuring";
        const request = ++requestGeneration;
        readKeyboardLevel(function (level) {
            // Ignore a response from a transition already cancelled.
            if (phase !== "measuring" || request !== requestGeneration) {
                return;
            }
            if (level === null || !fullscreenExists()) {
                phase = "idle";
                return;
            }
            savedLevel = level;
            phase = "fullscreen";
            // If Plasma was already set to Off, keep it off.
            if (level > 0) {
                setKeyboardLevel(0);
            }
        });
        return;
    }

    if (!isFullscreen && phase === "fullscreen") {
        phase = "restoring";
        const request = ++requestGeneration;
        readKeyboardLevel(function (currentLevel) {
            if (phase !== "restoring" || request !== requestGeneration) {
                return;
            }
            if (fullscreenExists()) {
                // Another window became fullscreen while this read was pending.
                phase = "fullscreen";
                return;
            }
            // Respect a user's manual change to a nonzero level while fullscreen.
            // Note: a manual change back to 0 is indistinguishable from our own
            // automatic 0 through the available KWin scripting interface.
            if (currentLevel === 0 && savedLevel !== null && savedLevel > 0) {
                setKeyboardLevel(savedLevel);
            }
            savedLevel = null;
            phase = "idle";
            if (fullscreenExists()) {
                updateBacklight();
            }
        });
    }
}

function watchWindow(window) {
    if (!window) {
        return;
    }
    window.fullScreenChanged.connect(updateBacklight);
    window.minimizedChanged.connect(updateBacklight);
}

workspace.windowAdded.connect(function (window) {
    watchWindow(window);
    updateBacklight();
});
workspace.windowRemoved.connect(updateBacklight);

const existingWindows = workspace.stackingOrder;
for (let i = 0; i < existingWindows.length; ++i) {
    watchWindow(existingWindows[i]);
}
updateBacklight();
