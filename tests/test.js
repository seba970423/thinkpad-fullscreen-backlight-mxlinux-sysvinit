// Node-only simulated KWin/PowerDevil tests. Does not touch real keyboard hardware.
const fs = require('fs');
const vm = require('vm');
const assert = require('assert/strict');
const path = require('path');
const main = fs.readFileSync(path.join(__dirname, '../contents/code/main.js'), 'utf8');

function signal() {
    const callbacks = [];
    return { connect(callback) { callbacks.push(callback); }, emit(...args) { for (const cb of callbacks) cb(...args); } };
}
function window(fullScreen = false) {
    return { fullScreen, minimized: false, specialWindow: false,
        fullScreenChanged: signal(), minimizedChanged: signal() };
}
function create(level = 2, initialWindows = []) {
    let brightness = level;
    const calls = [];
    const replies = [];
    const ws = { stackingOrder: initialWindows, windowAdded: signal(), windowRemoved: signal() };
    const ctx = { workspace: ws, print() {}, callDBus(service, objectPath, iface, method, ...args) {
        assert.equal(service, 'org.kde.Solid.PowerManagement');
        assert.equal(objectPath, '/org/kde/Solid/PowerManagement/Actions/KeyboardBrightnessControl');
        assert.equal(iface, 'org.kde.Solid.PowerManagement.Actions.KeyboardBrightnessControl');
        if (method === 'keyboardBrightness') {
            assert.equal(args.length, 1);
            assert.equal(typeof args[0], 'function');
            replies.push(args[0]);
        } else if (method === 'setKeyboardBrightnessSilent') {
            assert.equal(args.length, 1);
            assert(Number.isInteger(args[0]));
            brightness = args[0];
            calls.push(brightness);
        } else throw Error('Unknown API ' + method);
    } };
    vm.createContext(ctx);
    vm.runInContext(main, ctx);
    return {
        calls, replies, ws,
        level() { return brightness; },
        manual(level) { brightness = level; },
        flush() { while (replies.length) replies.shift()(brightness); },
        enter(w) { w.fullScreen = true; w.fullScreenChanged.emit(); },
        leave(w) { w.fullScreen = false; w.fullScreenChanged.emit(); },
        add(w) { ws.stackingOrder.push(w); ws.windowAdded.emit(w); },
        remove(w) { ws.stackingOrder = ws.stackingOrder.filter(x => x !== w); ws.windowRemoved.emit(); }
    };
}

// Level 2 -> 0 -> level 2.
{
    const a = window(); const x = create(2, [a]);
    x.enter(a); assert.equal(x.calls.length, 0); x.flush();
    assert.equal(x.level(), 0); x.leave(a); x.flush();
    assert.deepEqual(x.calls, [0,2]);
}
// Preserve original level 1.
{
    const a = window(true); const x = create(1, [a]); x.flush();
    assert.equal(x.level(), 0); x.leave(a); x.flush();
    assert.equal(x.level(), 1);
}
// Off stays off.
{
    const a = window(true); const x = create(0,[a]); x.flush(); x.leave(a); x.flush();
    assert.deepEqual(x.calls, []);
}
// Manual change during fullscreen is not overwritten on exit.
{
    const a = window(true); const x = create(2,[a]); x.flush();
    x.manual(1); x.leave(a); x.flush();
    assert.equal(x.level(),1); assert.deepEqual(x.calls,[0]);
}
// Multiple fullscreen windows count as a single session.
{
    const a = window(true); const b = window(true); const x=create(2,[a,b]); x.flush();
    x.leave(a); assert.equal(x.level(),0);
    x.leave(b); x.flush(); assert.equal(x.level(),2);
    assert.deepEqual(x.calls,[0,2]);
}
// Cancel a transition before PowerDevil replies.
{
    const a = window(); const x = create(2,[a]);
    x.enter(a); assert.equal(x.replies.length,1);
    x.leave(a); x.flush(); assert.deepEqual(x.calls,[]);
}
// Do not restore if another fullscreen window opens while a restore read is pending.
{
    const a = window(true); const b=window(); const x=create(2,[a]); x.flush();
    x.leave(a); x.add(b); x.enter(b); x.flush();
    assert.equal(x.level(),0);
    x.leave(b); x.flush(); assert.equal(x.level(),2);
}
// Old async reply cannot hijack a newer enter-fullscreen transition.
{
    const a = window(); const x=create(2,[a]);
    x.enter(a); x.leave(a); x.enter(a);
    assert.equal(x.replies.length,2);
    x.replies.shift()(2); // canceled old sample
    assert.deepEqual(x.calls,[]);
    x.flush(); assert.deepEqual(x.calls,[0]);
    x.leave(a); x.flush(); assert.equal(x.level(),2);
}
// Reject invalid read safely.
{
    const a = window(true); const x=create(2,[a]);
    x.replies.shift()('bad'); assert.deepEqual(x.calls,[]);
}
console.log('PASS: 9 simulated fullscreen/brightness scenarios.');
