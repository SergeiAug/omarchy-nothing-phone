pragma ComponentBehavior: Bound
// SPDX-License-Identifier: MIT
// Simplified from derekross/omarchy-mobile omamobile.switcher @1155a7c (Derek Ross et al.).
import QtQuick
import Quickshell
import Quickshell.Wayland
import "ui"
Item {
  id: root
  property var shell: null
  property var manifest: null
  property bool opened: false
  property var history: []
  readonly property var windows: ToplevelManager.toplevels.values.filter(window => !window.parent).slice().sort((a, b) => (root.history.indexOf(a) < 0 ? 99999 : root.history.indexOf(a)) - (root.history.indexOf(b) < 0 ? 99999 : root.history.indexOf(b)))
  function open(payloadJson) { opened = true }
  function close() { opened = false }
  function snapshot() { return JSON.stringify({opened: opened, windows: windows.length}) }
  function activateCard(index) {
    let window = windows[Number(index)]
    if (!window) return "unknown"
    window.activate()
    dismiss()
    return "ok"
  }
  function closeCard(index) {
    let window = windows[Number(index)]
    if (!window) return "unknown"
    window.close()
    return "ok"
  }
  function dismiss() { if (shell) shell.hide("spacewar.switcher"); else close() }
  function activated(window) { history = [window].concat(history.filter(w => w !== window && ToplevelManager.toplevels.values.indexOf(w) >= 0)) }
  Instantiator {
    model: ToplevelManager.toplevels
    delegate: Connections {
      required property var modelData
      target: modelData
      function onActivatedChanged() { if (modelData.activated) root.activated(modelData) }
    }
  }
  Navigation {}
  MobilePanel {
    opened: root.opened
    panelName: "spacewar-switcher"
    onDismissed: root.dismiss()
    PlainLabel { text: "Недавние приложения"; font.pixelSize: 24; width: parent.width }
    PlainLabel { anchors.centerIn: parent; visible: root.windows.length === 0; text: "Нет открытых окон" }
    ListView {
      id: cards
      anchors { top: parent.top; topMargin: 64; bottom: bottomActions.top; bottomMargin: 24; left: parent.left; right: parent.right }
      orientation: ListView.Horizontal
      spacing: 16
      snapMode: ListView.SnapToItem
      clip: true
      model: root.windows
      delegate: Rectangle {
        id: card
        required property var modelData
        required property int index
        width: cards.width * 0.82
        height: cards.height
        radius: 16
        color: "#242424"
        border.color: "#777777"
        PlainLabel {
          id: title
          anchors { top: parent.top; left: parent.left; right: parent.right; margins: 16 }
          height: 64
          text: card.modelData.title || card.modelData.appId
          wrapMode: Text.Wrap
          maximumLineCount: 2
        }
        ScreencopyView {
          anchors { top: title.bottom; left: parent.left; right: parent.right; bottom: buttons.top; margins: 8 }
          captureSource: root.opened ? card.modelData : null
          live: root.opened
        }
        PlainLabel {
          anchors.centerIn: parent
          width: parent.width - 32
          text: card.modelData.appId
          horizontalAlignment: Text.AlignHCenter
          opacity: 0.7
        }
        Row {
          id: buttons
          anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 12 }
          spacing: 8
          TouchButton {
            width: (buttons.width - 8) / 2; text: "Открыть"
            onClicked: root.activateCard(card.index)
          }
          TouchButton { width: (buttons.width - 8) / 2; text: "Закрыть"; onClicked: root.closeCard(card.index) }
        }
      }
    }
    Row {
      id: bottomActions
      anchors.bottom: parent.bottom
      spacing: 12
      TouchButton { width: (bottomActions.parent.width - 12) / 2; text: "Назад"; onClicked: root.dismiss() }
      TouchButton { width: (bottomActions.parent.width - 12) / 2; text: "Домой"; onClicked: Quickshell.execDetached(["spacewar-mobile", "home"]) }
    }
  }
}
