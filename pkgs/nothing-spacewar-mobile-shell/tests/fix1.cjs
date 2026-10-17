const assert = require('node:assert/strict');
const device = require('../plugins/spacewar.runtime/Device.js');
const policy = require('../plugins/spacewar.runtime/KeyboardPolicy.js');
assert.equal(device.safeLeft, 79);
assert.equal(device.safeTop, 56);
assert(device.safeLeft > device.cutout.x + device.cutout.diameter + 7);
assert(device.safeTop > device.cutout.y + device.cutout.diameter + 7);
for (const app of ['foot','Alacritty','kitty','com.mitchellh.ghostty','org.omarchy.terminal','org.omarchy.btop']) {
 const state = policy.create(), focus = {class:app,address:'a'};
 assert.equal(policy.update(state, focus, false, false), 'show', app);
 assert.equal(policy.update(state, focus, false, false), ''); // manual dismissal survives polling
 assert.equal(policy.update(state, {class:'nautilus',address:'b'}, false, true), 'hide');
}
for (const shown of [false,true]) {
 const state = policy.create(), focus = {class:'org.omarchy.terminal',address:'a'};
 policy.update(state, focus, false, false);
 assert.equal(policy.update(state, focus, true, shown), shown ? 'hide' : '');
 assert.equal(policy.update(state, {}, true, false), '');
 assert.equal(policy.update(state, focus, true, true), 'hide'); // late IM activation is suppressed
 assert.equal(policy.update(state, focus, false, false), shown ? 'show' : 'hide');
 assert.equal(policy.update(state, focus, false, shown), '');
}
assert(!policy.terminal('org.omarchy.screensaver'));
console.log('PASS: cutout geometry, terminal focus/manual dismissal, shade suppression/restoration');
