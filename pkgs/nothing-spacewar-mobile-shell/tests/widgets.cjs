// SPDX-License-Identifier: MIT
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const base=path.resolve(__dirname,'..');
const C=require('./owl-load.js').load('compiler.js');
const index=JSON.parse(fs.readFileSync(path.join(base,'owl-widgets/index.json')));
for(const w of index.widgets){
 const source=fs.readFileSync(path.join(base,'owl-widgets/widgets',w.id,'widget.owl'));
 assert.equal(crypto.createHash('sha256').update(source).digest('hex'),w.sha256,w.id);
 const result=C.compile(source.toString());
 assert.ok(result.name,w.id);
}
const H=require('../plugins/omamobile.home/HomeModel.js');
const layout=H.defaultLayout(['chromium','foot','org.gnome.Nautilus','btop']);
assert.equal(layout.grid.columns,4);
assert.ok(layout.pages[0].items.some(w=>w.type==='owl:simonschubert.analog-clock'));
assert.ok(layout.pages[0].items.some(w=>w.type==='owl:simonschubert.calendar'));
console.log('PASS: '+index.widgets.length+' shipped widget hashes + real OWL compiler; home defaults');
