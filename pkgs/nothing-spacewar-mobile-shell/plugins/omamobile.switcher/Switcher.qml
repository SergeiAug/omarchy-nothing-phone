// SPDX-License-Identifier: MIT
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import "../spacewar.runtime" as SW
import "../spacewar.runtime/Motion.js" as Motion
import qs.Ui

// Recent apps, after Android: every open window as a card with a live
// preview. Swipe sideways through them, tap one to switch to it, flick it up
// to close it. Home shows the home screen (an empty workspace) and leaves the
// apps open. Summoned by swiping up on the dock (omamobile.launcher).
//
// Every app has a screen (workspace) of its own (omamobile-launch). Hold a
// card for the two ways to change that: "Show with…" puts the app on another
// app's screen, where the two tile as Omarchy tiles them, and "Move to its
// own screen" gives it one back.
//
// Windows come from the Wayland foreign-toplevel list, which gives each one
// activate() and close(). Home and the hold actions need Hyprland: the
// actions find a window's Hyprland address and workspace through
// Quickshell.Hyprland and run omamobile-launch with them.
Item {
  id: root

  // Injected by the host.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "omamobile.switcher"

  property bool opened: false
  property real progress: opened ? 1 : 0
  property bool dragging: false
  Component.onCompleted: SW.Runtime.recents = root
  Component.onDestruction: SW.Runtime.recents = null
  function preview(value,active) { dragging=active; progress=value }
  Behavior on progress { enabled: !root.dragging; NumberAnimation { duration:200; easing.type:Easing.OutCubic } }


  // Newest first, like Android's recents.
  readonly property var windows: {
    var list = ToplevelManager.toplevels.values.slice()
    list.reverse()
    return list
  }

  // Host lifecycle (`shell summon` / `shell hide`).
  function open(payloadJson) { opened = true; dragging=false; progress=1 }
  function close() {
    opened = false; dragging=false; progress=0
    closeActions()
  }

  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  function switchTo(toplevel) {
    if (toplevel) toplevel.activate()
    dismiss()
  }

  function goHome() {
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"empty\" })"])
    // ...and the home screens (omamobile.home) back on their home page.
    Quickshell.execDetached(["qs", "ipc", "-p", Quickshell.shellDir, "call", "shell", "call", "omamobile.home", "goHome", ""])
    dismiss()
  }

  function snapshot() { return JSON.stringify({opened:opened,progress:progress,windows:windows.length}) }

  function closeAll() {
    var list = ToplevelManager.toplevels.values.slice()
    for (var i = 0; i < list.length; i++) list[i].close()
  }

  // ---------------------------------------------------------------- hold actions

  // The window whose actions are open, and which page: "menu" or "pick"
  // (the apps it can share a screen with).
  property var actionTarget: null
  property string actionPage: "menu"
  readonly property bool actionsOpen: actionTarget !== null && windows.indexOf(actionTarget) >= 0

  // Hyprland's view of a Wayland toplevel: its address and workspace. By the
  // toplevel mapping when Hyprland offers it, else by class and title.
  function hyprlandFor(toplevel) {
    if (!toplevel) return null
    var list = Hyprland.toplevels.values
    var fallback = null
    for (var i = 0; i < list.length; i++) {
      const candidate = list[i]
      if (candidate.wayland === toplevel) return candidate
      const ipc = candidate.lastIpcObject || ({})
      if (!fallback && candidate.title === toplevel.title && ipc["class"] === toplevel.appId) fallback = candidate
    }
    return fallback
  }

  function addressOf(toplevel) {
    var hypr = hyprlandFor(toplevel)
    return hypr && hypr.address ? String(hypr.address) : ""
  }

  function workspaceOf(toplevel) {
    var hypr = hyprlandFor(toplevel)
    return hypr && hypr.workspace ? hypr.workspace.id : null
  }

  // Other open windows on the same screen.
  function screenMates(toplevel) {
    var ws = workspaceOf(toplevel)
    if (ws === null || ws === undefined) return []
    return windows.filter(function(other) { return other !== toplevel && workspaceOf(other) === ws })
  }

  // Windows on other screens, which this one can join.
  function partners(toplevel) {
    var ws = workspaceOf(toplevel)
    return windows.filter(function(other) {
      return other !== toplevel && (ws === null || ws === undefined || workspaceOf(other) !== ws)
    })
  }

  function openActions(toplevel) {
    if (!toplevel) return
    Hyprland.refreshToplevels()
    actionPage = "menu"
    actionTarget = toplevel
  }

  function closeActions() {
    actionTarget = null
    actionPage = "menu"
  }

  // This window onto other's screen: omamobile-launch moves it there by
  // address and tiles the two.
  function showWith(toplevel, other) {
    var a = addressOf(toplevel)
    var b = addressOf(other)
    if (a && b) Quickshell.execDetached(["omamobile-launch", "show-with", a, b])
    closeActions()
    dismiss()
  }

  function moveToOwnScreen(toplevel) {
    var a = addressOf(toplevel)
    if (a) Quickshell.execDetached(["omamobile-launch", "own-screen", a])
    closeActions()
    dismiss()
  }

  function windowLabel(toplevel) {
    if (!toplevel) return ""
    return (toplevel.appId || "App") + (toplevel.title ? "  " + toplevel.title : "")
  }

  readonly property color foreground: Commons.Color.menu.text
  readonly property int touch: Math.max(44, Style.space(44))

  PanelWindow {
    id: overlay

    visible: root.opened || root.progress > 0
    mask: Region { x:Motion.P.edge; y:SW.Runtime.barHeight; width: overlay.width-Motion.P.edge*2; height: SW.Runtime.ready && root.opened && !root.dragging ? Math.max(0,(SW.Runtime.oskShown ? SW.Runtime.keyboardTop : overlay.height)-SW.Runtime.barHeight-Motion.P.bottomEdge) : 0 }
    contentItem.opacity: root.progress
    contentItem.scale: 0.85 + 0.15*root.progress
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "omamobile-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    onVisibleChanged: if (visible) cards.positionViewAtBeginning()

    Rectangle {
      anchors.fill: parent
      color: Commons.Color.menu.background
      opacity: 0.94
    }

    // Tapping empty space goes back to whatever was on screen.
    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Item {
      anchors.fill: parent
      focus: root.opened
      Keys.onEscapePressed: {
        if (root.actionsOpen) root.closeActions()
        else root.dismiss()
      }
    }

    Text {
      anchors.centerIn: parent
      visible: root.windows.length === 0
      textFormat: Text.PlainText
      text: "No recent apps"
      color: Qt.darker(root.foreground, 1.4)
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
    }

    ListView {
      id: cards

      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: -Style.space(24)
      height: Math.round(parent.height * 0.68)

      orientation: ListView.Horizontal
      spacing: Style.space(18)
      snapMode: ListView.SnapToItem
      highlightRangeMode: ListView.StrictlyEnforceRange
      preferredHighlightBegin: (width - cardWidth) / 2
      preferredHighlightEnd: (width + cardWidth) / 2
      boundsBehavior: Flickable.StopAtBounds
      model: root.windows

      readonly property int cardWidth: Math.round(width * 0.72)

      delegate: Item {
        id: slot
        required property var modelData
        required property int index

        width: cards.cardWidth
        height: cards.height

        // Title row: app and window title.
        Text {
          id: title
          anchors.left: card.left
          anchors.right: closeButton.left
          anchors.bottom: card.top
          anchors.bottomMargin: Style.space(8)
          opacity: card.opacity
          textFormat: Text.PlainText
          text: (slot.modelData.appId || "") + (slot.modelData.title ? "  " + slot.modelData.title : "")
          elide: Text.ElideRight
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Rectangle {
          id: closeButton
          anchors.right: card.right
          anchors.bottom: card.top
          width: root.touch; height: root.touch
          radius: width/2
          color: Commons.Color.background
          Text { anchors.centerIn: parent; text: "×"; color: root.foreground; font.pixelSize: 28 }
          MouseArea { anchors.fill: parent; onClicked: slot.modelData.close() }
        }

        Rectangle {
          id: card

          width: parent.width
          height: parent.height - Math.max(title.height, closeButton.height) - Style.space(8)
          y: Math.max(title.height, closeButton.height) + Style.space(8) + drag.lift
          radius: Style.cornerRadius
          clip: true
          color: Commons.Color.background
          border.width: 2
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
          opacity: 1 - Math.min(0.8, Math.abs(drag.lift) / height)

          ScreencopyView {
            anchors.fill: parent
            anchors.margins: card.border.width
            captureSource: root.opened || root.dragging ? slot.modelData : null
            live: true
          }

          // Tap to switch; hold for "Show with…" and "Move to its own screen".
          TapHandler {
            onTapped: root.switchTo(slot.modelData)
            onLongPressed: root.openActions(slot.modelData)
          }

          // Flick up to close; anything shorter springs back.
          DragHandler {
            id: drag
            target: null
            xAxis.enabled: false
            property real lift: 0
            property double lastMotion: 0
            onActiveTranslationChanged: { lift = Math.min(0, activeTranslation.y); lastMotion=Date.now() }
            minimumPointCount: 1; maximumPointCount: 1
            property bool canceled: false
            onCanceled: { canceled=true; springBack.start() }
            onActiveChanged: {
              if (active) { canceled=false; springBack.stop(); return }
              if (canceled) return
              if (Motion.closeCard(-lift, Date.now()-lastMotion<Motion.P.velocityAge ? -centroid.velocity.y : 0, card.height)) {
                closeOut.start()
              } else {
                springBack.start()
              }
            }
          }

          NumberAnimation {
            id: springBack
            target: drag; property: "lift"; to: 0
            duration: 160; easing.type: Easing.OutCubic
          }

          SequentialAnimation {
            id: closeOut
            NumberAnimation { target: drag; property: "lift"; to: -card.height * 1.2; duration: 160; easing.type: Easing.InCubic }
            ScriptAction { script: { slot.modelData.close(); drag.lift = 0 } }
          }
        }
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: cards.bottom
      anchors.topMargin: Style.space(12)
      text: root.dragging ? "Потяните выше и отпустите для недавних" : "Смахните вверх или нажмите ×, чтобы закрыть"
      width: parent.width - Motion.P.edge*2
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      color: root.foreground
      font.pixelSize: 14
      textFormat: Text.PlainText
    }

    // Bottom actions: clear everything, or go home.
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Motion.P.bottomEdge + Style.space(16)
      spacing: Style.space(16)

      Repeater {
        model: [
          { label: "Закрыть все", visible: root.windows.length > 0, action: "clear" },
          { label: "Домой", visible: true, action: "home" }
        ]

        delegate: BorderSurface {
          id: bottomButton
          required property var modelData
          visible: modelData.visible
          width: Math.max(root.touch * 2.6, label.implicitWidth + Style.space(32))
          height: root.touch
          radius: Style.cornerRadius
          color: tap.pressed ? Commons.Color.menu.selected || Commons.Color.background : Commons.Color.background

          Text {
            id: label
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: bottomButton.modelData.label
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          TapHandler {
            id: tap
            onTapped: bottomButton.modelData.action === "home" ? root.goHome() : root.closeAll()
          }
        }
      }
    }

    // Hold actions: a sheet over the cards. Tapping outside it closes it.
    Item {
      id: actionLayer
      anchors.fill: parent
      visible: root.actionsOpen

      Rectangle {
        anchors.fill: parent
        color: Commons.Color.menu.background
        opacity: 0.6
      }

      MouseArea {
        anchors.fill: parent
        onClicked: root.closeActions()
      }

      BorderSurface {
        id: actionCard
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Style.space(16)
        anchors.bottomMargin: Motion.P.bottomEdge + Style.space(16)
        height: actionColumn.implicitHeight + Style.space(24)
        radius: Style.cornerRadius
        color: Commons.Color.background

        // Swallows taps between the rows, so they don't close the sheet.
        MouseArea { anchors.fill: parent }

        Column {
          id: actionColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(12)
          spacing: Style.space(6)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.actionPage === "pick" ? "Show with…" : root.windowLabel(root.actionTarget)
            elide: Text.ElideRight
            color: Qt.darker(root.foreground, 1.3)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            bottomPadding: Style.space(6)
          }

          // The menu.
          SheetRow {
            visible: root.actionPage === "menu"
            enabled: root.actionsOpen && root.partners(root.actionTarget).length > 0
            text: "Show with…"
            hint: enabled ? "Share the screen with another open app" : "No other app is open"
            onActivated: root.actionPage = "pick"
          }

          SheetRow {
            visible: root.actionPage === "menu" && root.actionsOpen && root.screenMates(root.actionTarget).length > 0
            text: "Move to its own screen"
            hint: "Stop sharing the screen"
            onActivated: root.moveToOwnScreen(root.actionTarget)
          }

          // The apps to share a screen with.
          Repeater {
            model: root.actionPage === "pick" && root.actionsOpen ? root.partners(root.actionTarget) : []

            delegate: SheetRow {
              required property var modelData
              text: modelData.appId || "App"
              hint: modelData.title || ""
              onActivated: root.showWith(root.actionTarget, modelData)
            }
          }

          SheetRow {
            text: root.actionPage === "pick" ? "Back" : "Cancel"
            onActivated: {
              if (root.actionPage === "pick") root.actionPage = "menu"
              else root.closeActions()
            }
          }
        }
      }
    }
  }

  // One row of the hold-actions sheet: a label over a hint.
  component SheetRow: Rectangle {
    id: sheetRow

    property string text: ""
    property string hint: ""
    signal activated()

    width: parent ? parent.width : 0
    height: Math.max(root.touch, rowText.implicitHeight + (rowHint.visible ? rowHint.implicitHeight : 0) + Style.space(16))
    radius: Style.cornerRadius
    color: rowTap.pressed ? (Commons.Color.menu.selected || Commons.Color.background) : "transparent"
    opacity: enabled ? 1 : 0.45

    Column {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)

      Text {
        id: rowText
        width: parent.width
        textFormat: Text.PlainText
        text: sheetRow.text
        elide: Text.ElideRight
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
      }

      Text {
        id: rowHint
        width: parent.width
        visible: sheetRow.hint.length > 0
        textFormat: Text.PlainText
        text: sheetRow.hint
        elide: Text.ElideRight
        color: Qt.darker(root.foreground, 1.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      id: rowTap
      anchors.fill: parent
      enabled: sheetRow.enabled
      onClicked: sheetRow.activated()
    }
  }
}
