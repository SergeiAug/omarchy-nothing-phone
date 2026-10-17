import QtQuick
import qs.Commons as Commons
Rectangle {
  id: root
  property string title: ""
  property string subtitle: ""
  property string glyph: ""
  property bool active: false
  property bool details: false
  signal clicked()
  signal settings()
  implicitHeight: 88
  radius: 18
  color: active ? Commons.Color.accent : Commons.Color.menu.selectedBackground
  opacity: enabled ? 1 : 0.45
  property color ink: active ? Commons.Color.background : Commons.Color.menu.text
  PlainLabel { x: 16; y: 10; text: root.glyph; font.pixelSize: 25; color: root.ink }
  PlainLabel { x: 16; y: 41; width: parent.width - 24 - (root.details ? 48 : 0); text: root.title; font.pixelSize: 17; font.bold: true; color: root.ink }
  PlainLabel { x: 16; y: 63; width: parent.width - 24 - (root.details ? 48 : 0); text: root.subtitle; font.pixelSize: 14; color: root.ink; opacity: 0.8 }
  MouseArea {
    anchors.fill: parent
    anchors.rightMargin: root.details ? 48 : 0
    onClicked: root.clicked()
    onPressAndHold: root.settings()
  }
  PlainLabel { visible: root.details; anchors.right: parent.right; width: 48; height: parent.height; text: "›"; font.pixelSize: 28; color: root.ink; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
  MouseArea { visible: root.details; anchors.right: parent.right; width: 48; height: parent.height; onClicked: root.settings() }
}
