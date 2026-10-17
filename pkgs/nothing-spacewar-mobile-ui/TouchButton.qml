import QtQuick
import qs.Commons as Commons
Rectangle {
  id: root
  property string text: ""
  signal clicked()
  implicitWidth: 144
  implicitHeight: 56
  radius: 12
  color: touch.pressed ? Commons.Color.menu.selectedBackground : Commons.Color.background
  border.width: 1
  border.color: Commons.Color.menu.text
  opacity: enabled ? 1 : 0.4
  PlainLabel {
    anchors.fill: parent
    anchors.margins: 8
    text: root.text
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    wrapMode: Text.Wrap
  }
  MouseArea { id: touch; anchors.fill: parent; onClicked: root.clicked() }
}
