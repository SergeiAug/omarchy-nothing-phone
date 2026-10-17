const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const M = require('../plugins/spacewar.runtime/Motion.js');
function swipe(height, distance, duration, releaseVelocity, canceled=false) {
 let s=M.begin('bottom',270,height,0,height);
 for(let t=20;t<=duration;t+=20) s=M.move(s,270,height-distance*t/duration,t);
 s.velocity=releaseVelocity;
 return M.finish(s,duration+10,canceled);
}
for(const height of [960,1200]) {
 assert.equal(swipe(height,height*.40,1000,480),'recents');
 assert.equal(swipe(height,height*.35,1000,400),'home');
 assert.equal(swipe(height,height*.5,300,1800),'home');
 assert.equal(swipe(height,height*.5,1200,400,true),'cancel');
 assert.equal(swipe(height,height*.4,1000,-900),'home');
}
assert.equal(M.P.bottomEdge,30);
assert.equal(M.P.edge,16);
const runtime=fs.readFileSync(__dirname+'/../plugins/spacewar.runtime/Runtime.qml','utf8');
const load=runtime.match(/onLoaded: \{ try \{([^]*?)\} catch/)[1];
for(const enabled of [false,true]) {
 const root={}; vm.runInNewContext(load,{root,text:()=>JSON.stringify({gestureLogging:enabled,backEnabled:false})});
 assert.equal(root.gestureLogging,enabled); assert.equal(root.backEnabled,false);
}
const gestures=fs.readFileSync(__dirname+'/../plugins/spacewar.gestures/Gestures.qml','utf8');
const log=gestures.match(/function logGesture\(phase, result\) \{([^]*?)\n  \}/)[1];
for(const enabled of [false,true]) {
 const logs=[];
 const context={SW:{Runtime:{gestureLogging:enabled}},gesture:{tracking:true,kind:'bottom',distance:456,velocity:400,held:false},
 console:{warn:s=>logs.push(JSON.parse(s.replace('spacewar-gesture ','')))},phase:'finish',result:'recents'};
 vm.runInNewContext("(function(){"+log+"})()",context);
 assert.equal(logs.length,Number(enabled));
 if(enabled) assert.deepEqual(logs[0],{phase:'finish',kind:'bottom',distance:456,velocity:400,held:false,result:'recents'});
}
const home=fs.readFileSync(__dirname+'/../plugins/omamobile.home/Home.qml','utf8');
assert.match(home,/id:appsButton[^]*?anchors.bottomMargin:Motion.P.bottomEdge/);
console.log('PASS: long slow release, fast home, relative height, cancel/reversal, 30px home drawer separation, live log switch and fields');
