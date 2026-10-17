// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.UPower
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import "../spacewar.runtime" as SW
import "../spacewar.runtime/Motion.js" as Motion
import "StatusModel.js" as StatusModel
import "../spacewar.runtime/Device.js" as Device

// Phone status bar, a full `bar` option that replaces omarchy.bar.
//
// The phone has no window list, tray or workspaces to show, so this bar only
// reports state: the clock on the left and connectivity, do-not-disturb and
// battery on the right. The middle stays empty for the camera cutout. The
// whole strip is one touch target: a tap or a downward pull opens the quick
// settings sheet.
Item {
  id: root

  // Injected by the host (see shell.qml configureBar).
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  Component.onCompleted: SW.Runtime.barHeight = Math.max(barSize, Device.safeTop)
  onBarSizeChanged: SW.Runtime.barHeight = Math.max(barSize, Device.safeTop)
  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var barConfig: ({})

  // Scalar bar state the host mirrors to other plugins (notifications and the
  // OSD place themselves clear of the bar with these).
  readonly property bool barHidden: false
  readonly property string position: "top"
  readonly property bool vertical: false
  readonly property string fontFamily: Style.font.family
  // A phone status bar is a touch target, and the Pixel's camera cutout sits
  // in it, so it is never thinner than 44 logical px.
  readonly property int barSize: Math.max(Motion.P.bar, Style.bar.sizeHorizontal)

  readonly property color foreground: Commons.Color.bar.text
  readonly property color background: Commons.Color.bar.background
  readonly property color urgent: Commons.Color.bar.active

  function setting(name, fallback) {
    var value = barConfig ? barConfig[name] : undefined
    return value === undefined || value === null || value === "" ? fallback : value
  }

  readonly property string clockFormat: String(setting("clockFormat", "HH:mm"))
  readonly property bool showBatteryPercent: setting("showBatteryPercent", true) !== false
  readonly property string quickSettingsId: String(setting("quickSettings", "omamobile.quicksettings"))

  // A full bar may read the notification service's do-not-disturb state
  // through the host's narrow proxy.
  readonly property var notifications: shell && typeof shell.firstPartyServiceFor === "function"
    ? shell.firstPartyServiceFor("omarchy.notifications") : null
  readonly property bool doNotDisturb: notifications ? notifications.doNotDisturb === true : false

  // ---------------------------------------------------------------- state

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  readonly property var networkDevices: Networking.devices ? Networking.devices.values : []
  readonly property var wifiDevice: StatusModel.findDevice(networkDevices, DeviceType.Wifi)
  readonly property var wiredDevice: StatusModel.findDevice(networkDevices, DeviceType.Wired)
  readonly property var wifiNetwork: StatusModel.connectedNetwork(wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : [])
  readonly property string networkKind: {
    if (wiredDevice && wiredDevice.connected) return "ethernet"
    if (wifiNetwork) return "wifi"
    return wifiDevice && !Networking.wifiEnabled ? "off" : "disconnected"
  }
  readonly property string networkIcon: StatusModel.networkIcon(networkKind,
    wifiNetwork ? Math.round((wifiNetwork.signalStrength || 0) * 100) : -1)

  // Cellular signal. STUB: Quickshell.Networking has no modem backend and the
  // Pixel 7 Pro's modem has no mainline driver yet, so there is nothing to read.
  // When a ModemManager-backed source exists, set `available` and `strength`
  // (0-100) from it and the icon appears; until then it renders nothing.
  readonly property QtObject cellular: QtObject {
    readonly property bool available: false
    readonly property int strength: -1
  }

  readonly property var btAdapter: Bluetooth.defaultAdapter
  readonly property bool bluetoothConnected: {
    var devices = Bluetooth.devices ? Bluetooth.devices.values : []
    for (var i = 0; i < devices.length; i++)
      if (devices[i] && devices[i].connected) return true
    return false
  }

  readonly property var battery: UPower.displayDevice
  readonly property bool hasBattery: !!battery && battery.isPresent === true
  readonly property int batteryPercent: hasBattery ? Math.round(battery.percentage * 100) : -1
  readonly property bool charging: hasBattery && !UPower.onBattery
  readonly property string batteryIcon: StatusModel.batteryIcon(batteryPercent, charging,
    hasBattery && battery.state === UPowerDeviceState.FullyCharged)

  // ---------------------------------------------------------------- host API

  // The host calls these on whatever bar is active. A phone bar hosts no
  // widget panels, so every per-widget route answers "not here".
  function summonBarWidget(id) { return false }
  function hideBarWidget(id) { return false }
  function isBarWidgetOpen(id) { return false }
  function panelWidgetIdAt(section, index) { return "" }
  function debugBarGeometry() { return [{ position: position, size: barSize }] }

  function openQuickSettings() {
    if (shell && typeof shell.summon === "function")
      shell.summon(quickSettingsId, JSON.stringify({ source: "bar" }))
  }

  function toggleQuickSettings() {
    if (shell && typeof shell.toggle === "function")
      shell.toggle(quickSettingsId, JSON.stringify({ source: "bar" }))
  }

  // Edge-swipe gestures and hardware keys reach the sheet through here, e.g.
  // `omarchy-shell omamobile.bar pullDown` from a Hyprland gesture bind.
  IpcHandler {
    target: "omamobile.bar"

    function pullDown(): string {
      root.openQuickSettings()
      return "ok"
    }

    function toggleQuickSettings(): string {
      root.toggleQuickSettings()
      return "ok"
    }
  }

  // ---------------------------------------------------------------- surface

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: barWindow

      required property var modelData
      screen: modelData

      anchors { top: true; left: true; right: true }
      implicitHeight: Math.max(root.barSize, Device.safeTop)
      exclusionMode: ExclusionMode.Auto
      color: root.background
      WlrLayershell.namespace: "omarchy-bar"
      WlrLayershell.layer: WlrLayer.Top

      Text {
        x: parent.width / 2 - 22; width: 44; height: root.barSize
        text: "󰌌"; textFormat: Text.PlainText
        color: root.foreground; font.pixelSize: Style.font.iconLarge
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
      }
      Item {
        width: parent.width; height: root.barSize
        anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: Math.max(SW.Runtime.safeLeft, Number(root.setting("safeLeft", SW.Runtime.safeLeft)))
        anchors.rightMargin: Style.spacing.huge

        Text {
          id: clockText
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: Qt.formatDateTime(clock.date, root.clockFormat)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Row {
          id: status
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xl

          StatusGlyph {
            visible: root.doNotDisturb
            text: "󰂛"
          }

          StatusGlyph {
            visible: !!root.btAdapter && root.btAdapter.enabled
            text: root.bluetoothConnected ? "󰂱" : "󰂯"
          }

          StatusGlyph {
            visible: root.cellular.available
            text: StatusModel.cellularIcon(root.cellular.strength)
          }

          StatusGlyph {
            visible: root.networkIcon !== ""
            text: root.networkIcon
            opacity: root.networkKind === "off" || root.networkKind === "disconnected" ? 0.55 : 1
          }

          Row {
            visible: root.hasBattery
            spacing: Style.spacing.xs
            anchors.verticalCenter: parent.verticalCenter

            StatusGlyph {
              text: root.batteryIcon
              color: root.batteryPercent >= 0 && root.batteryPercent <= 10 && !root.charging ? root.urgent : root.foreground
            }

            Text {
              visible: root.showBatteryPercent
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.batteryPercent + "%"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }
        }
      }


    }
  }

  component StatusGlyph: Text {
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.iconLarge
  }
}
