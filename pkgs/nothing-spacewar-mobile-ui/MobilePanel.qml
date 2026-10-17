import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons as Commons
PanelWindow {
  id: panel
  property bool opened: false
  property int compactHeight: 0
  property bool slideFromTop: false
  property real offset: opened || !slideFromTop ? 0 : -height
  Behavior on offset { NumberAnimation { id: slide; duration: 180; easing.type: Easing.OutCubic } }
  property string panelName: "spacewar-mobile"
  signal dismissed()
  default property alias contents: body.data
  visible: opened || slide.running
  anchors { top: true; bottom: compactHeight <= 0; left: true; right: true }
  implicitHeight: compactHeight
  margins.top: slideFromTop ? Commons.Style.bar.sizeHorizontal : 0
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  WlrLayershell.namespace: panelName
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
  Rectangle {
    anchors.fill: parent
    color: Commons.Color.menu.background
    radius: panel.compactHeight > 0 ? 24 : 0
    transform: Translate { y: panel.offset }
  }
  Item {
    id: body
    transform: Translate { y: panel.offset }
    anchors.fill: parent
    anchors.topMargin: panel.compactHeight > 0 ? 8 : 48
    anchors.leftMargin: 24
    anchors.rightMargin: 24
    anchors.bottomMargin: panel.compactHeight > 0 ? 8 : 36
    focus: panel.opened
    Keys.onEscapePressed: panel.dismissed()
  }
}
