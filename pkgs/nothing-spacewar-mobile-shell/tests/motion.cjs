const assert=require('node:assert/strict');
const M=require('../plugins/spacewar.runtime/Motion.js');
function swipe(points, end, cancel=false) {
 let s=M.begin('bottom',270,1200,0);
 for(const [time,y] of points) s=M.move(s,270,y,time);
 s=M.tick(s,end);
 return M.finish(s,end,cancel);
}
assert.equal(swipe([[40,1188]],50),'cancel');
assert.equal(swipe([[300,1080]],320),'home');
assert.equal(swipe([[20,1160]],25),'home');
assert.equal(swipe([[100,1080]],350),'recents');
assert.equal(swipe([[100,1080]],150,true),'cancel');
assert.equal(swipe([[20,1160]],250),'cancel');
assert.equal(swipe([[100,1080],[200,1195]],220),'cancel');
assert.equal(M.finish({tracking:false},20),'cancel');
assert.equal(M.closeCard(55,1000,600),true);
assert.equal(M.closeCard(60,0,600),false);
assert.equal(M.closeCard(160,0,600),true);
console.log('PASS: short, slow, flick, paused, canceled, stale velocity, reversal, idle, card distance/velocity');

let diagonal=M.begin('bottom',270,1200,0);
diagonal=M.move(diagonal,450,1100,100);
assert.equal(M.finish(diagonal,110),'cancel');
let continuous=M.begin('bottom',270,1200,0);
for(let t=20;t<=600;t+=20) continuous=M.move(continuous,270,1200-t/5,t);
assert.equal(M.finish(continuous,610),'home');
