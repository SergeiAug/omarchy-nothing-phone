const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(__dirname + '/../plugins/spacewar.runtime/Runtime.qml', 'utf8');
const body = source.match(/function back\(\) \{([\s\S]*?)\n  \}/)[1];
for (const selected of ['launcher', 'shade', 'recents', 'osk', 'app']) {
  const calls = [];
  const context = { oskShown: ['launcher','shade','recents','osk'].includes(selected),
    command: args => calls.push(args.join(' ')),
    Quickshell: {execDetached: args => calls.push(args.join(' '))} };
  for (const name of ['launcher','shade','recents']) {
    context[name] = {opened: ['launcher','shade','recents'].indexOf(name) >= ['launcher','shade','recents'].indexOf(selected)
      && ['launcher','shade','recents'].includes(selected), dismiss: () => calls.push(name)};
  }
  vm.runInNewContext(body, context);
  assert.deepEqual(calls, [selected === 'osk' ? 'onscreen-keyboard hide' : selected === 'app' ? 'spacewar-shell-back' : selected]);
}
console.log('PASS: back priority: launcher, shade, recents, OSK, application helper');
