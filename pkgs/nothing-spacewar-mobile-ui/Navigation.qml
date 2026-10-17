pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
Item {
  function action(name) { Quickshell.execDetached(["spacewar-mobile", name]) }
  id: root
  Variants {
    model: Quickshell.screens
    PanelWindow {
      required property var modelData
      screen: modelData
      anchors { bottom: true; left: true; right: true }
      implicitHeight: 16
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "spacewar-navigation"
      WlrLayershell.layer: WlrLayer.Overlay
      Rectangle { anchors.centerIn: parent; width: 120; height: 4; radius: 2; color: "#aaaaaa" }
      MouseArea {
        id: touch
        anchors.fill: parent
        property point origin
        property bool handled: false
        onPressed: mouse => { origin = Qt.point(mouse.x, mouse.y); handled = false; hold.start() }
        onPositionChanged: mouse => { if (Math.abs(mouse.x - origin.x) > 12 || Math.abs(mouse.y - origin.y) > 12) hold.stop() }
        onReleased: mouse => {
          hold.stop()
          if (handled) return
          const dx = mouse.x - origin.x
          const dy = mouse.y - origin.y
          if (Math.abs(dx) > 48 && Math.abs(dx) > Math.abs(dy)) root.action(dx < 0 ? "next" : "previous")
          else if (dy < -12) root.action("home")
        }
        onCanceled: { hold.stop(); handled = true }
        Timer { id: hold; interval: 450; onTriggered: { touch.handled = true; root.action("switcher") } }
      }
    }
  }
}
