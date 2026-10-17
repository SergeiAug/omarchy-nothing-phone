// SPDX-License-Identifier: MIT
// Logical px at 540x1200. Cube's 72px pause gate/180ms dwell and
// Simon's narrow idle input region/full drag region define the contract.
var P = { axisSlop:10, axisRatio:1.15, velocityAge:100, edge: 16, bottomEdge: 30, bar: 44, home: 72, hold: 180, jitter: 36, pauseSpeed: 60, flick: 900,
          minFlick: 24, back: 72, closeFraction: 0.25, cardFlick: 54, travel: 360, recentsFraction: 0.38, recentsSpeed: 650 }
function begin(kind, x, y, time, height) {
  return { height: height || 1200, started: time, kind: kind, x: x, y: y, last: time, distance: 0, velocity: 0,
           anchor: 0, pauseAt: time, held: false, tracking: true }
}
function move(s, x, y, time) {
  if (!s.tracking) return s
  s = Object.assign({},s)
  var d = Math.max(0, s.kind === "bottom" ? s.y-y : s.kind === "shade" ? y-s.y : Math.abs(x-s.x))
  if (s.kind === "shade") d=y-s.y
  if(s.kind === "bottom" && !s.axis && Math.max(d,Math.abs(x-s.x))>=P.axisSlop) {
    s.axis=true; s.rejected=Math.abs(x-s.x)*P.axisRatio>d
  }
  var v = (d-s.distance)*1000/Math.max(1,time-s.last)
  if (Math.abs(d-s.anchor)>P.jitter || d<P.home) { s.anchor=d; s.pauseAt=time }
  s.distance=d; s.velocity=v; s.last=time
  return tick(s,time)
}
function tick(s,time) {
  s = Object.assign({},s)
  if (s.tracking && s.kind === "bottom" && s.distance>=P.home && time-s.pauseAt>=P.hold && (time-s.last>=P.hold || Math.abs(s.velocity)<P.pauseSpeed)) s.held=true
  return s
}
function finish(s,time,canceled) {
  if (!s.tracking || s.rejected || canceled) return "cancel"
  var v=time-s.last<P.velocityAge ? s.velocity : 0
  if (s.kind === "bottom") return s.distance>=P.home || (s.distance>=P.minFlick && v>P.flick) ? (s.held || (s.distance>=s.height*P.recentsFraction && s.distance*1000/Math.max(1,time-s.started)<=P.recentsSpeed && Math.abs(v)<=P.recentsSpeed) ? "recents" : "home") : "cancel"
  return s.distance>=P.back || (s.distance>=P.minFlick && v>P.flick) ? "commit" : "cancel"
}
function closeCard(distance, velocity, height) {
  return distance >= height*P.closeFraction || (distance>=P.cardFlick && velocity>P.flick)
}
if (typeof module !== "undefined") module.exports = {P:P,begin:begin,move:move,tick:tick,finish:finish,closeCard:closeCard}
