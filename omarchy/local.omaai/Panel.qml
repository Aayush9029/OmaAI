import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
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

  readonly property bool running: snapshot.running === true
  readonly property bool ready: snapshot.ready === true
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.58)
  readonly property color faint: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)
  readonly property color accent: ready ? "#34d399" : (running ? "#fbbf24" : muted)

  function commandFor(args) {
    return [String(settings.command || "omaai")].concat(args)
  }

  function refresh() {
    if (statusProc.running) return
    statusProc.command = commandFor(["status"])
    statusProc.running = true
  }

  function runAction(args) {
    if (actionProc.running) return
    lastError = ""
    actionProc.command = commandFor(args)
    actionProc.running = true
  }

  function stateText() {
    if (lastError !== "") return "OmaAI unavailable"
    if (ready) return "Model ready"
    if (running) return "Model loading"
    if (String(snapshot.state) === "failed") return "Model failed"
    return "Model unloaded"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) refresh()

  Timer {
    interval: Math.max(1000, Number(settings.refreshIntervalMs || 3000))
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.snapshot = JSON.parse(String(text || "{}"))
          root.lastError = ""
        } catch (error) {
          root.lastError = "Invalid local AI response"
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") root.lastError = String(text).trim()
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") root.lastError = String(text).trim()
    }
    onRunningChanged: if (!running) root.refresh()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function load(): string { root.runAction(["start"]); return "ok" }
    function unload(): string { root.runAction(["stop"]); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "✦"
    fontFamily: "JetBrainsMono Nerd Font"
    fontSize: Style.bar.iconFont * 1.8
    active: root.ready
    tooltipText: root.stateText()
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(600))

    Column {
      id: content
      width: parent.width
      spacing: Style.space(12)

      PanelHero {
        width: parent.width
        title: "OmaAI"
        meta: root.stateText()
        foreground: root.foreground
        fontFamily: bar ? bar.fontFamily : Style.font.family
        iconOpacity: root.running ? 1.0 : 0.55
        trailingControl: Component {
          Column {
            spacing: Style.space(2)
            Text {
              anchors.right: parent.right
              text: "RAM  " + Number(root.snapshot.ramUsedGiB || 0).toFixed(1) + " / " + Number(root.snapshot.ramTotalGiB || 0).toFixed(1) + " GB"
              color: root.foreground
              font.family: bar ? bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            Text {
              anchors.right: parent.right
              text: Number(root.snapshot.gpuPercent || 0) + "% GPU  ·  " + Number(root.snapshot.vramUsedGiB || 0).toFixed(1) + " / " + Number(root.snapshot.vramTotalGiB || 0).toFixed(1) + " GB"
              color: root.muted
              font.family: bar ? bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }
        iconComponent: Component {
          Text {
            text: "✦"
            color: root.accent
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: Style.font.displayLarge
          }
        }
      }

      Rectangle {
        width: parent.width
        implicitHeight: modelColumn.implicitHeight + Style.space(24)
        radius: Style.space(12)
        color: root.faint

        Column {
          id: modelColumn
          anchors.fill: parent
          anchors.margins: Style.space(12)
          spacing: Style.space(5)
          Text {
            width: parent.width
            text: String(root.snapshot.model || "llama.cpp model")
            color: root.foreground
            elide: Text.ElideRight
            font.family: bar ? bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            text: String(root.snapshot.details || "GGUF · Vulkan")
            color: root.muted
            font.family: bar ? bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      RowLayout {
        width: parent.width
        spacing: Style.space(8)
        ActionButton {
          Layout.fillWidth: true
          text: root.running ? "Unload" : "Load"
          glyph: root.running ? "󰅖" : "󰐊"
          destructive: root.running
          enabled: !actionProc.running
          onClicked: root.runAction([root.running ? "stop" : "start"])
        }
        ActionButton {
          Layout.fillWidth: true
          text: "Restart"
          glyph: "󰜉"
          enabled: root.running && !actionProc.running
          onClicked: root.runAction(["restart"])
        }
        ActionButton {
          Layout.fillWidth: true
          text: "Open UI"
          glyph: "󰖟"
          enabled: root.ready
          onClicked: root.runAction(["open"])
        }
      }

      Text {
        text: "OPENAI-COMPATIBLE ENDPOINTS"
        color: root.muted
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      EndpointRow {
        label: "This computer"
        value: String(root.snapshot.localUrl || "")
        endpoint: "local"
      }
      EndpointRow {
        label: "Local network"
        value: String(root.snapshot.lanUrl || "")
        endpoint: "lan"
      }
      EndpointRow {
        label: "Tailscale"
        value: String(root.snapshot.tailscaleUrl || "")
        endpoint: "tailscale"
      }

      ActionButton {
        width: parent.width
        text: "Copy API key"
        glyph: "󰌆"
        enabled: true
        onClicked: root.runAction(["copy-key"])
      }

      Text {
        visible: root.lastError !== ""
        width: parent.width
        text: root.lastError
        color: "#fb7185"
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }

  component EndpointRow: Rectangle {
    id: endpointRow
    property string label: ""
    property string value: ""
    property string endpoint: "local"

    width: parent.width
    implicitHeight: endpointColumn.implicitHeight + Style.space(18)
    radius: Style.space(10)
    color: endpointMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14) : root.faint
    opacity: value !== "" ? 1 : 0.45

    Column {
      id: endpointColumn
      anchors.left: parent.left
      anchors.right: copyGlyph.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(2)
      Text {
        text: endpointRow.label
        color: root.foreground
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Text {
        width: parent.width
        text: endpointRow.value || "Not connected"
        color: root.muted
        elide: Text.ElideMiddle
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
    Text {
      id: copyGlyph
      anchors.right: parent.right
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: "󰆏"
      color: root.foreground
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: Style.font.body
    }
    MouseArea {
      id: endpointMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: endpointRow.value !== ""
      cursorShape: Qt.PointingHandCursor
      onClicked: root.runAction(["copy-url", endpointRow.endpoint])
    }
  }

  component ActionButton: Rectangle {
    id: action
    property string text: ""
    property string glyph: ""
    property bool destructive: false
    signal clicked()

    implicitHeight: Style.space(42)
    radius: Style.space(10)
    color: actionMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14) : root.faint
    opacity: enabled ? 1 : 0.45

    Row {
      anchors.centerIn: parent
      spacing: Style.space(7)
      Text {
        text: action.glyph
        color: action.destructive ? "#fb7185" : root.foreground
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: Style.font.body
      }
      Text {
        text: action.text
        color: action.destructive ? "#fb7185" : root.foreground
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }
    }
    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: action.enabled
      cursorShape: Qt.PointingHandCursor
      onClicked: action.clicked()
    }
  }
}
