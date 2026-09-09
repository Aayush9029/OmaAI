import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import qs.Ui as Ui

Panel {
  id: app
  moduleName: "local.omaai"
  ipcTarget: "local.omaai"
  manageIpc: false

  property var snapshot: ({
    state: "stopped",
    running: false,
    ready: false,
    localUrl: "http://127.0.0.1:8080/v1",
    lanUrl: "",
    tailscaleUrl: "",
    ramUsedGiB: 0,
    ramTotalGiB: 0,
    gpuPercent: -1,
    vramUsedGiB: 0,
    vramTotalGiB: 0,
    model: "llama.cpp model",
    details: "GGUF · Vulkan"
  })
  property string lastError: ""
  property string actionError: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property int desiredPower: -1
  readonly property bool powerOn: desiredPower >= 0 ? desiredPower === 1 : running
  readonly property bool busy: actionProc.running || desiredPower >= 0
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool running: snapshot.running === true
  readonly property bool ready: snapshot.ready === true
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color muted: Qt.darker(foreground, 1.4)

  function commandFor(args) {
    return [String(settings.command || "omaai")].concat(args)
  }

  function refresh() {
    if (statusProc.running) return
    statusProc.command = commandFor(["status"])
    statusProc.running = true
  }

  function runAction(args) {
    if (busy) return
    actionError = ""
    if (args[0] === "start") desiredPower = 1
    else if (args[0] === "stop") desiredPower = 0
    actionProc.command = commandFor(args)
    actionProc.running = true
  }

  function stateText() {
    if (lastError !== "") return "OmaAI unavailable"
    if (desiredPower === 0) return "Turning off"
    if (desiredPower === 1) return "Turning on"
    if (ready) return "Model ready"
    if (running) return "Model loading"
    if (String(snapshot.state) === "failed") return "Model failed"
    return "Turned off"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) { cursorActive = false; selectedIndex = 0; refresh() }

  Timer {
    interval: Math.max(1000, Number(settings.refreshIntervalMs || 3000))
    running: true
    repeat: true
    onTriggered: app.refresh()
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          app.snapshot = JSON.parse(String(text || "{}"))
          if (!actionProc.running) app.desiredPower = -1
          app.lastError = ""
        } catch (error) {
          app.lastError = "Invalid local AI response"
          if (!actionProc.running) app.desiredPower = -1
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") app.lastError = String(text).trim()
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        app.desiredPower = -1
        app.actionError = String(actionStderr.text || "").trim() || "Action failed. Please try again."
      }
      app.refresh()
    }
  }

  IpcHandler {
    target: app.ipcTarget
    function open(): void { app.open() }
    function close(): void { app.close() }
    function toggle(): void { app.toggle() }
    function refresh(): string { app.refresh(); return "ok" }
    function load(): string { app.runAction(["start"]); return "ok" }
    function unload(): string { app.runAction(["stop"]); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: app.bar
    text: "✦"
    fontFamily: "JetBrainsMono Nerd Font"
    fontSize: Style.bar.iconFont * 1.8
    active: app.ready
    tooltipText: app.stateText()
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) app.refresh()
      else app.toggle()
    }
  }

  function moveCursor(delta) {
    cursorActive = true
    selectedIndex = Math.max(0, Math.min(6, selectedIndex + delta))
  }

  function activateCursor() {
    if (selectedIndex === 0) runAction([powerOn ? "stop" : "start"])
    else if (selectedIndex === 1 && running) runAction(["restart"])
    else if (selectedIndex === 2 && ready) runAction(["open"])
    else if (selectedIndex >= 3 && selectedIndex <= 5) {
      var urls = [snapshot.localUrl, snapshot.lanUrl, snapshot.tailscaleUrl]
      if (urls[selectedIndex - 3]) runAction(["copy-url", ["local", "lan", "tailscale"][selectedIndex - 3]])
    } else if (selectedIndex === 6) runAction(["copy-key"])
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: app
    bar: app.bar
    open: app.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { app.moveCursor(dy || dx) }
      onTabRequested: function(direction) { app.moveCursor(direction) }
      onActivateRequested: app.activateCursor()
      onCloseRequested: app.close()

      Column {
        id: content
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          id: hero
          width: parent.width
          title: "OmaAI"
          meta: app.stateText()
          foreground: app.foreground
          fontFamily: app.fontFamily
          iconOpacity: app.powerOn ? 1 : 0.5
          iconComponent: Component {
            Text {
              text: "✦"
              color: app.foreground
              font.family: app.fontFamily
              font.pixelSize: Style.font.display
            }
          }
          trailingControl: Component {
            ToggleSwitch {
              id: powerSwitch
              checked: app.powerOn
              busy: app.busy
              foreground: app.foreground
              hasCursor: app.cursorActive && app.selectedIndex === 0
              onHovered: function(on) { if (on) { app.cursorActive = true; app.selectedIndex = 0 } }
              onToggled: app.runAction([app.powerOn ? "stop" : "start"])
              PanelToolTip {
                visible: powerSwitch.containsMouse
                text: app.powerOn ? "Turn off · stays off after restart" : "Turn on · load at login"
                fontFamily: app.fontFamily
              }
            }
          }
        }

        PanelSeparator { foreground: app.foreground }

        Column {
          width: parent.width
          spacing: Style.space(5)
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: String(app.snapshot.model || "llama.cpp model")
            color: app.foreground
            elide: Text.ElideMiddle
            font.family: app.fontFamily
            font.pixelSize: Style.font.body
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: String(app.snapshot.details || "GGUF · Vulkan")
            color: app.muted
            elide: Text.ElideRight
            font.family: app.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          MetricRow {
            label: "Memory"
            value: Number(app.snapshot.ramUsedGiB || 0).toFixed(1) + " / " + Number(app.snapshot.ramTotalGiB || 0).toFixed(1) + " GB"
          }
          MetricRow {
            label: "GPU"
            value: Number(app.snapshot.gpuPercent) >= 0 ? Number(app.snapshot.gpuPercent) + "%" : "Unavailable"
          }
          MetricRow {
            label: "VRAM"
            value: Number(app.snapshot.vramTotalGiB) > 0 ? Number(app.snapshot.vramUsedGiB || 0).toFixed(1) + " / " + Number(app.snapshot.vramTotalGiB).toFixed(1) + " GB" : "Unavailable"
          }
        }

        RowLayout {
          width: parent.width
          spacing: Style.space(8)
          NativeButton {
            Layout.fillWidth: true
            text: "Restart"
            iconText: "󰜉"
            cursorIndex: 1
            enabled: app.running && !app.busy
            onClicked: app.runAction(["restart"])
          }
          NativeButton {
            Layout.fillWidth: true
            text: "Open UI"
            iconText: "󰖟"
            cursorIndex: 2
            enabled: app.ready && !app.busy
            onClicked: app.runAction(["open"])
          }
        }

        PanelSeparator { foreground: app.foreground }
        PanelSectionHeader {
          text: "API ENDPOINTS"
          foreground: app.foreground
          fontFamily: app.fontFamily
        }
        Column {
          width: parent.width
          spacing: Style.space(4)
          EndpointRow { label: "This computer"; value: String(app.snapshot.localUrl || ""); endpoint: "local"; cursorIndex: 3; glyph: "󰍹" }
          EndpointRow { label: "Local network"; value: String(app.snapshot.lanUrl || ""); endpoint: "lan"; cursorIndex: 4; glyph: "󰈀" }
          EndpointRow { label: "Tailscale"; value: String(app.snapshot.tailscaleUrl || ""); endpoint: "tailscale"; cursorIndex: 5; glyph: "󰒍" }
        }
        PanelSeparator { foreground: app.foreground }
        NativeButton {
          width: parent.width
          text: "Copy API key"
          iconText: "󰌆"
          cursorIndex: 6
          enabled: !app.busy
          onClicked: app.runAction(["copy-key"])
        }
        Text {
          visible: text !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: app.actionError || app.lastError
          color: app.bar ? app.bar.urgent : Color.foreground
          wrapMode: Text.Wrap
          font.family: app.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  component MetricRow: RowLayout {
    property string label: ""
    property string value: ""
    width: parent.width
    Text { text: label; color: app.muted; font.family: app.fontFamily; font.pixelSize: Style.font.body }
    Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: value; color: app.foreground; font.family: app.fontFamily; font.pixelSize: Style.font.body }
  }

  component NativeButton: Ui.Button {
    property int cursorIndex: -1
    foreground: app.foreground
    fontFamily: app.fontFamily
    bordered: true
    opacity: enabled ? 1 : 0.45
    hasCursor: app.cursorActive && app.selectedIndex === cursorIndex
    onHovered: function(on) { if (on) { app.cursorActive = true; app.selectedIndex = cursorIndex } }
  }

  component EndpointRow: CursorSurface {
    id: endpointRow
    property string label: ""
    property string value: ""
    property string endpoint: "local"
    property string glyph: ""
    property int cursorIndex: -1
    width: parent.width
    implicitHeight: endpointColumn.implicitHeight + Style.space(18)
    foreground: app.foreground
    hasCursor: app.cursorActive && app.selectedIndex === cursorIndex
    opacity: value !== "" ? 1 : 0.45

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)
      Text { text: endpointRow.glyph; color: app.muted; font.family: app.fontFamily; font.pixelSize: Style.font.heading }
      Column {
        id: endpointColumn
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text { width: parent.width; text: endpointRow.label; color: app.foreground; font.family: app.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
        Text { width: parent.width; text: endpointRow.value || "Not connected"; color: app.muted; font.family: app.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideMiddle }
      }
      Text { text: "󰆏"; color: app.foreground; font.family: app.fontFamily; font.pixelSize: Style.font.icon }
    }
    MouseArea {
      id: endpointMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: endpointRow.value !== "" && !app.busy
      cursorShape: Qt.PointingHandCursor
      onEntered: { app.cursorActive = true; app.selectedIndex = endpointRow.cursorIndex }
      onClicked: app.runAction(["copy-url", endpointRow.endpoint])
    }
    PanelToolTip { visible: endpointMouse.containsMouse; text: "Copy " + endpointRow.label.toLowerCase() + " URL"; fontFamily: app.fontFamily }
  }
}
