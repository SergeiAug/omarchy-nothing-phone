pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons as Commons
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import qs.Ui
import "ui"
Item {
  id: root
  property var shell: null
  property var manifest: null
  property bool opened: false
  property string errorText: ""
  property var phoneState: ({layout: "", keyboard: null, rotated: null, dnd: null, brightness: null, flashAvailable: false})
  readonly property var wifi: Networking.devices.values.find(device => device.type === DeviceType.Wifi) || null
  readonly property string wifiName: wifi ? (wifi.networks.values.find(network => network.connected)?.name || "") : ""
  readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
  readonly property string bluetoothName: Bluetooth.devices.values.filter(device => device.connected).map(device => device.name).join(", ")
  readonly property var sink: Pipewire.defaultAudioSink
  PwObjectTracker { objects: root.sink ? [root.sink] : [] }
  function refresh() { if (opened && !status.running && !control.running) status.running = true }
  function open(payloadJson) { opened = true; refresh() }
  function close() { opened = false }
  function snapshot() { return JSON.stringify({opened: opened, offset: panel.offset, height: panel.height, state: phoneState}) }
  function dismiss() { if (shell) shell.hide("spacewar.shade"); else close() }
  function action(name, value) {
    if (control.running) return
    errorText = ""
    control.command = value === undefined ? ["spacewar-mobile", name] : ["spacewar-mobile", name, String(value)]
    control.running = true
  }
  Process {
    id: control
    stderr: StdioCollector { onStreamFinished: root.errorText = text }
    onExited: (exitCode, exitStatus) => { if (exitCode !== 0 && !root.errorText) root.errorText = "Не удалось выполнить действие"; root.refresh() }
  }
  Process {
    id: status
    command: ["spacewar-mobile", "shade-state"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.phoneState = JSON.parse(text) }
        catch (error) { root.errorText = "Не удалось прочитать состояние" }
      }
    }
  }
  Timer { interval: 5000; repeat: true; running: root.opened; onTriggered: root.refresh() }
  Variants {
    model: Quickshell.screens
    PanelWindow {
      required property var modelData
      screen: modelData
      anchors.top: true
      implicitWidth: 140
      implicitHeight: Commons.Style.bar.sizeHorizontal
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      WlrLayershell.namespace: "spacewar-shade-touch"
      WlrLayershell.layer: WlrLayer.Overlay
      PlainLabel { anchors.centerIn: parent; text: "⌄"; font.pixelSize: 16; color: Commons.Color.bar.text }
      MouseArea { anchors.fill: parent; onClicked: Quickshell.execDetached(["spacewar-mobile", "shade"]) }
    }
  }
  MobilePanel {
    id: panel
    opened: root.opened
    slideFromTop: true
    panelName: "spacewar-shade"
    onDismissed: root.dismiss()
    compactHeight: Math.min(screen.height - Commons.Style.bar.sizeHorizontal, controls.height + 16)
    Flickable {
      anchors.fill: parent
      contentHeight: controls.height
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      Column {
        id: controls
        width: parent.width
        spacing: 12
        Item {
          width: parent.width; height: 48
          PlainLabel { anchors.centerIn: parent; text: "Быстрые настройки"; font.pixelSize: 22; font.bold: true }
          MouseArea {
            anchors.fill: parent
            property real startY: 0
            onPressed: mouse => { startY = mouse.y }
            onReleased: mouse => { if (mouse.y - startY < -24) root.dismiss() }
          }
        }
        Grid {
          width: parent.width; columns: 2; spacing: 12
          QuickTile {
            width: (parent.width - 12) / 2
            title: "Wi-Fi"; glyph: Networking.wifiEnabled ? "󰖩" : "󰖪"
            active: Networking.wifiEnabled
            subtitle: !root.wifi ? "Нет адаптера" : !active ? "Выключен" : root.wifiName || "Не подключён"
            enabled: !!root.wifi; details: true
            onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
            onSettings: root.action("network")
          }
          QuickTile {
            width: (parent.width - 12) / 2
            title: "Bluetooth"; glyph: active ? "󰂯" : "󰂲"
            active: !!root.adapter && root.adapter.enabled
            subtitle: !root.adapter ? "Нет адаптера" : !active ? "Выключен" : root.bluetoothName || "Включён"
            enabled: !!root.adapter; details: true
            onClicked: root.adapter.enabled = !root.adapter.enabled
            onSettings: root.action("bluetooth")
          }
          QuickTile {
            width: (parent.width - 12) / 2
            title: "Поворот"; glyph: "󰑤"; active: root.phoneState.rotated === true
            subtitle: root.phoneState.rotated === null ? "Недоступен" : active ? "Альбомный" : "Портретный"
            enabled: root.phoneState.rotated !== null; onClicked: root.action("rotate")
          }
          QuickTile {
            width: (parent.width - 12) / 2
            title: "RU / EN"; glyph: "󰌌"; active: root.phoneState.layout === "RU"
            subtitle: root.phoneState.layout || "Недоступен"
            enabled: !!root.phoneState.layout; onClicked: root.action("layout")
          }
          QuickTile {
            width: (parent.width - 12) / 2
            title: "Клавиатура"; glyph: "󰌌"; active: root.phoneState.keyboard === true
            subtitle: root.phoneState.keyboard === null ? "Недоступна" : active ? "Показана" : "Скрыта"
            enabled: root.phoneState.keyboard !== null; onClicked: root.action("keyboard")
          }
          QuickTile {
            width: (parent.width - 12) / 2
            title: "Не беспокоить"; glyph: "󰂛"; active: root.phoneState.dnd === true
            subtitle: root.phoneState.dnd === null ? "Недоступно" : active ? "Включено" : "Выключено"
            enabled: root.phoneState.dnd !== null; onClicked: root.action("dnd")
          }
          QuickTile {
            visible: root.phoneState.flashAvailable === true
            width: (parent.width - 12) / 2
            title: "Фонарик"; glyph: "󰉗"; active: root.phoneState.flash === true
            subtitle: active ? "Включён" : "Выключен"; onClicked: root.action("flash")
          }
        }
        Column {
          width: parent.width; spacing: 0
          PlainLabel { text: "Яркость   " + (root.phoneState.brightness === null ? "Недоступна" : Math.round(brightness.liveValue) + "%"); font.pixelSize: 16 }
          PanelSlider {
            id: brightness
            width: parent.width; height: 48
            minimum: 1; maximum: 100; integer: true
            value: root.phoneState.brightness === null ? 1 : root.phoneState.brightness
            enabled: root.phoneState.brightness !== null
            trackColor: Commons.Color.menu.selectedBackground; fillColor: Commons.Color.accent; knobColor: Commons.Color.accent
            onReleased: value => root.action("brightness", Math.round(value))
          }
          PlainLabel { text: "Громкость   " + (!root.sink || !root.sink.audio ? "Недоступна" : root.sink.audio.muted ? "Без звука" : Math.round(volume.liveValue * 100) + "%"); font.pixelSize: 16 }
          Row {
            width: parent.width; spacing: 12
            TouchButton { width: 48; height: 48; text: root.sink && root.sink.audio && root.sink.audio.muted ? "󰝟" : "󰕾"; enabled: !!root.sink && !!root.sink.audio; onClicked: root.sink.audio.muted = !root.sink.audio.muted }
            PanelSlider {
              id: volume
              width: parent.width - 60; height: 48
              value: root.sink && root.sink.audio ? root.sink.audio.volume : 0
              enabled: !!root.sink && !!root.sink.audio
              trackColor: Commons.Color.menu.selectedBackground; fillColor: Commons.Color.accent; knobColor: Commons.Color.accent
              onMoved: value => { root.sink.audio.volume = value }
            }
          }
        }
        Row {
          width: parent.width; spacing: 12
          TouchButton { width: (parent.width - 12) / 2; text: "󰅖  Закрыть окно"; onClicked: root.action("close") }
          TouchButton { width: (parent.width - 12) / 2; text: "󰐥  Питание"; onClicked: root.action("power") }
        }
        PlainLabel { visible: !!root.errorText; width: parent.width; text: root.errorText; wrapMode: Text.Wrap; color: Commons.Color.urgent }
        Item {
          width: parent.width; height: 48
          Rectangle { anchors.centerIn: parent; width: 64; height: 5; radius: 3; color: Commons.Color.menu.text }
          MouseArea {
            anchors.fill: parent
            property real startY: 0
            onPressed: mouse => { startY = mouse.y }
            onReleased: mouse => { if (mouse.y - startY < -24) root.dismiss() }
            onClicked: root.dismiss()
          }
        }
      }
    }
  }
}
