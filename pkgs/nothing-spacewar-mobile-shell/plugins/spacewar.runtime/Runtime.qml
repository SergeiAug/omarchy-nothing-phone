// SPDX-License-Identifier: MIT
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Device.js" as Device
import "KeyboardPolicy.js" as KeyboardPolicy
QtObject {
  id: root
  readonly property real safeLeft: Device.safeLeft
  property real barHeight:Device.safeTop
  property var keyboardPolicy: KeyboardPolicy.create()
  property bool shadeActive: !!shade && (shade.opened || shade.dragging || shade.reveal > 0)
  property bool readingKeyboard: false
  property var keyboardRestoreOverride: null
  onShadeActiveChanged: {
    if (shadeActive && !keyboardPolicy.suspended) {
      readingKeyboard = true
      keyboardSnapshot.running = true
    } else updateKeyboard()
  }
  property var keyboardSnapshot: Process {
    command: ["omarchy-shell", "onscreen-keyboard", "status"]
    property bool shown: root.oskShown
    stdout: StdioCollector {
      onStreamFinished: { try { keyboardSnapshot.shown = JSON.parse(text).shown === true } catch(e) {} }
    }
    onExited: {
      root.keyboardPolicy.suspended = true
      root.keyboardPolicy.restore = root.keyboardRestoreOverride === null ? shown : root.keyboardRestoreOverride
      root.keyboardRestoreOverride = null
      root.readingKeyboard = false
      root.updateKeyboard()
    }
  }
  property var focusedApp: ({})
  property bool workspaceOccupied: true
  function updateKeyboard() {
    if (readingKeyboard) return
    var action = KeyboardPolicy.update(keyboardPolicy, focusedApp, shadeActive, oskShown)
    if (action) command(["onscreen-keyboard", action])
  }
  function setKeyboard(show) {
    if (shadeActive) {
      keyboardPolicy.restore = show
      if (readingKeyboard) keyboardRestoreOverride = show
    } else command(["onscreen-keyboard", show ? "show" : "hide"])
  }
  function toggleKeyboard() { if (!shadeActive) command(["onscreen-keyboard", "toggle"]) }
  property var launcher: null
  property var homeView: null
  property var shade: null
  property var recents: null
  property string owner: ""
  property bool backEnabled: true
  property bool gestureLogging: true
  function command(args) { Quickshell.execDetached(["omarchy-shell"].concat(args)) }
  function home() {
    command(["shell", "hide", "omamobile.quicksettings"])
    command(["shell", "hide", "omamobile.switcher"])
    command(["shell", "hide", "omamobile.launcher"])
    command(["shell", "call", "omamobile.home", "goHome", ""])
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"empty\" })"])
    command(["onscreen-keyboard", "hide"])
  }
  function back() {
    if (launcher && launcher.opened) launcher.dismiss()
    else if (shade && shade.opened) shade.dismiss()
    else if (recents && recents.opened) recents.dismiss()
    else if (oskShown) command(["onscreen-keyboard", "hide"])
    else Quickshell.execDetached(["spacewar-shell-back"])
  }
  property var options: FileView {
    path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omarchy/spacewar-shell.json"
    watchChanges: true; printErrors: false
    onFileChanged: reload()
    onLoaded: { try { var config = JSON.parse(text()); root.backEnabled = config.backEnabled !== false; root.gestureLogging = config.gestureLogging !== false } catch(e) {} }
  }
  property bool ready: false
  property bool oskShown: false
  property real keyboardTop: 0
  property string monitor: ""
  property string dialogGeometry: ""
  function fitDialogs() {
    var signature = ready + ":" + oskShown + ":" + keyboardTop
    if (ready && signature !== dialogGeometry) {
      dialogGeometry = signature
      Quickshell.execDetached(["hyprctl", "eval", "spacewar_fit_dialogs()"])
    }
  }
  property var poll: Timer {
    interval: 150; running: true; repeat: true; triggeredOnStart: true
    onTriggered: if (!probe.running) probe.running = true
  }
  property var probe: Process {
    command: ["spacewar-shell-geometry"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var value = JSON.parse(text)
          root.ready = value.ready === true
          root.oskShown = value.shown === true
          root.keyboardTop = value.top || 0
          root.monitor = value.monitor || ""
          root.focusedApp = value.focus || ({})
          root.workspaceOccupied = value.occupied === true
          root.updateKeyboard()
          root.fitDialogs()
        } catch (e) { root.ready = false }
      }
    }
    onExited: function(code) { if (code !== 0) root.ready = false }
  }
}
