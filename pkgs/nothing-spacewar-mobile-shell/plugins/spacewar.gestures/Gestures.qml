// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../spacewar.runtime" as SW
import "../spacewar.runtime/input" as Input
import "../spacewar.runtime/Motion.js" as Motion
Item {
  id: root
  IpcHandler {
    target:"spacewar.gestures"
    function feed(arg: string): string {
      var e=JSON.parse(arg)
      if(e.phase === "begin") root.start(e.x,e.y)
      else if(e.phase === "move") root.move(e.x,e.y)
      else root.finish(e.phase === "cancel")
      return snapshot()
    }
    function snapshot(): string { return JSON.stringify({dragging:root.dragging,owner:SW.Runtime.owner,ready:SW.Runtime.ready,available:root.available,backEnabled:SW.Runtime.backEnabled,focus:SW.Runtime.focusedApp,keyboardPolicy:SW.Runtime.keyboardPolicy,shade:SW.Runtime.shadeActive}) }
  }
  property var shell: null
  property var manifest: null
  property var gesture: ({tracking:false})
  readonly property bool dragging: gesture.tracking === true
  readonly property real available: SW.Runtime.ready ? (SW.Runtime.oskShown ? SW.Runtime.keyboardTop : overlay.height) : 0
  function cancel() { finish(true) }
  function start(x,y) {
    var kind = y >= overlay.height-Motion.P.bottomEdge ? "bottom" : "back"
    gesture = Motion.begin(kind,x,y,Date.now(),overlay.height)
    logGesture("begin", "tracking")
    SW.Runtime.owner = kind
    if (kind === "bottom" && SW.Runtime.recents) SW.Runtime.recents.preview(0, true)
  }
  function move(x,y) {
    gesture = Motion.move(gesture,x,y,Date.now())
    if (gesture.kind === "bottom" && SW.Runtime.recents)
      SW.Runtime.recents.preview(Math.min(1,gesture.distance/Motion.P.travel),true)
  }
  function logGesture(phase, result) {
    if (!SW.Runtime.gestureLogging || !gesture.tracking) return
    console.warn("spacewar-gesture " + JSON.stringify({phase:phase, kind:gesture.kind,
      distance:Math.round(gesture.distance), velocity:Math.round(gesture.velocity),
      held:gesture.held, result:result}))
  }
  function finish(canceled) {
    var result=Motion.finish(gesture,Date.now(),canceled)
    if (gesture.kind === "bottom" && SW.Runtime.recents) SW.Runtime.recents.preview(result === "recents" ? 1 : 0,false)
    logGesture("finish", result)
    gesture = ({tracking:false}); SW.Runtime.owner = ""
    if (result === "home") SW.Runtime.home()
    else if (result === "recents") SW.Runtime.command(["shell","summon","omamobile.switcher","{}"])
    else if (result === "commit") SW.Runtime.back()
  }
  Timer { interval: 30; running: root.dragging; repeat: true
    onTriggered: root.gesture = Motion.tick(root.gesture,Date.now()) }
  Connections { target: SW.Runtime
    function onBackEnabledChanged() { if (!SW.Runtime.backEnabled && root.gesture.kind === "back") root.cancel() }
    function onReadyChanged() { if (!SW.Runtime.ready) root.cancel() }
    function onOskShownChanged() { root.cancel() }
  }
  Component.onDestruction: SW.Runtime.owner = ""
  PanelWindow {
    id: overlay
    anchors { top:true; bottom:true; left:true; right:true }
    exclusionMode: ExclusionMode.Ignore; color:"transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "spacewar-edge"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {
      x:0; y:SW.Runtime.barHeight
      width: root.dragging ? overlay.width : 0
      height: root.dragging ? Math.max(0,root.available-SW.Runtime.barHeight) : 0
      Region { x:0; y:overlay.height-Motion.P.bottomEdge; width: !SW.Runtime.oskShown && SW.Runtime.ready && SW.Runtime.owner !== "shade" ? overlay.width : 0; height:Motion.P.bottomEdge }
      Region { x:0; y:SW.Runtime.barHeight; width: SW.Runtime.backEnabled && SW.Runtime.ready && !SW.Runtime.owner ? Motion.P.edge : 0; height:Math.max(0,root.available-SW.Runtime.barHeight-Motion.P.bottomEdge) }
      Region { x:overlay.width-Motion.P.edge; y:SW.Runtime.barHeight; width: SW.Runtime.backEnabled && SW.Runtime.ready && !SW.Runtime.owner ? Motion.P.edge : 0; height:Math.max(0,root.available-SW.Runtime.barHeight-Motion.P.bottomEdge) }
    }
    Input.EdgeInput {
      anchors.fill:parent
      enabled: SW.Runtime.ready && SW.Runtime.owner !== "shade"
      onBegan: function(x,y) { root.start(x,y) }
      onMoved: function(x,y) { root.move(x,y) }
      onEnded: function(canceled) { root.finish(canceled) }
    }
    Rectangle {
      visible: root.dragging && root.gesture.kind === "back"
      x: root.gesture.x < overlay.width/2 ? Math.min(root.gesture.distance,80)-30 : overlay.width-Math.min(root.gesture.distance,80)
      y: root.gesture.y-28; width:40; height:56; radius:20; color:"#cc333333"
      Text { anchors.centerIn:parent; text:root.gesture.x < overlay.width/2 ? "‹" : "›"; color:"white"; font.pixelSize:32; textFormat:Text.PlainText }
    }
  }
}
