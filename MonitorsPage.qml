import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var strings: null
  property string pluginDir: ""
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family

  property var monitors: []
  property bool loading: false
  property bool saving: false
  property bool dirty: false
  property bool pendingApply: false
  property string statusText: ""
  property string errorText: ""

  readonly property string monitorsPath: Quickshell.env("HOME") + "/.config/hypr/monitors.lua"

  function t(key) {
    return strings ? strings.t(key) : key
  }

  function refresh() {
    if (monitorsProc.running) return
    loading = true
    errorText = ""
    monitorsProc.running = false
    monitorsProc.running = true
  }

  function updateMonitor(index, key, value) {
    var next = monitors.slice()
    var row = Object.assign({}, next[index] || {})
    row[key] = value
    next[index] = row
    monitors = next
    dirty = true
    statusText = ""
    errorText = ""
    applyTimer.restart()
  }

  function apply() {
    if (monitors.length === 0) return
    if (saving) {
      pendingApply = true
      return
    }
    if (!dirty) return
    saving = true
    pendingApply = false
    statusText = t("schema.saving")
    errorText = ""
    var payload = Model.monitorsPayload(monitors)
    dirty = false
    saveProc.command = ["bash", pluginDir + "/bin/set-monitors", payload]
    saveProc.running = false
    saveProc.running = true
  }

  Timer {
    id: applyTimer
    interval: 300
    repeat: false
    onTriggered: root.apply()
  }

  function openEditor() {
    Quickshell.execDetached(["omarchy-launch-config-editor", monitorsPath])
  }

  Process {
    id: monitorsProc
    command: ["hyprctl", "-j", "monitors"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.dirty || root.saving) return
        root.monitors = Model.monitorsFromHyprctl(text)
      }
    }
    stderr: StdioCollector {
      id: monitorsErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode !== 0 && root.monitors.length === 0) {
        root.errorText = String(monitorsErr.text || "").trim() || root.t("monitors.error")
      }
    }
  }

  Process {
    id: saveProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      id: saveErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.saving = false
      if (exitCode === 0) {
        root.statusText = root.t("monitors.saved")
        root.errorText = ""
        if (root.dirty || root.pendingApply) {
          root.pendingApply = false
          root.dirty = true
          root.applyTimer.restart()
        }
      } else {
        root.dirty = true
        root.errorText = String(saveErr.text || "").trim() || root.t("monitors.error")
        root.statusText = ""
      }
    }
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.spacing.lg

    Column {
      Layout.fillWidth: true
      spacing: Style.spacing.sm

      Text {
        textFormat: Text.PlainText
        text: root.t("monitors.title")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.t("monitors.description")
        color: Qt.darker(root.foreground, 1.35)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }
    }

    PanelSeparator {
      Layout.fillWidth: true
      foreground: root.foreground
    }

    Text {
      Layout.fillWidth: true
      visible: root.loading && root.monitors.length === 0
      textFormat: Text.PlainText
      text: root.t("monitors.loading")
      color: Qt.darker(root.foreground, 1.3)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      Layout.fillWidth: true
      visible: !root.loading && root.monitors.length === 0
      textFormat: Text.PlainText
      text: root.t("monitors.empty")
      color: Qt.darker(root.foreground, 1.3)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Flickable {
      Layout.fillWidth: true
      Layout.fillHeight: true
      contentWidth: width
      contentHeight: listColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      visible: root.monitors.length > 0

      Column {
        id: listColumn
        width: parent.width
        spacing: Style.spacing.xl

        Repeater {
          model: root.monitors

          delegate: Column {
            width: listColumn.width
            spacing: Style.spacing.md

            required property var modelData
            required property int index

            Column {
              width: parent.width
              spacing: Style.spacing.xs

              Text {
                textFormat: Text.PlainText
                text: String(modelData.output || "")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: String(modelData.description || "")
                color: Qt.darker(root.foreground, 1.35)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            Flow {
              width: parent.width
              spacing: Style.spacing.lg

              Dropdown {
                label: root.t("monitors.scale")
                value: String(modelData.scale)
                options: Model.scaleOptions(modelData.scale)
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onChanged: function(value) { root.updateMonitor(index, "scale", value) }
              }

              Dropdown {
                label: root.t("monitors.mode")
                value: Model.normalizeMode(modelData.mode)
                options: Model.modeOptions(modelData.availableModes, modelData.mode)
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onChanged: function(value) { root.updateMonitor(index, "mode", value) }
              }

              Dropdown {
                label: root.t("monitors.position")
                value: String(modelData.position || "auto")
                options: Model.positionOptions(modelData.position)
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onChanged: function(value) { root.updateMonitor(index, "position", value) }
              }
            }

            PanelSeparator {
              width: parent.width
              visible: index < root.monitors.length - 1
              foreground: root.foreground
            }
          }
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.md

      Button {
        text: root.t("monitors.openEditor")
        bordered: true
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onClicked: root.openEditor()
      }

      Button {
        text: root.t("monitors.refresh")
        bordered: true
        enabled: !root.loading && !root.saving
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onClicked: {
          root.dirty = false
          root.refresh()
        }
      }

      Item { Layout.fillWidth: true }

      Text {
        textFormat: Text.PlainText
        visible: root.statusText !== "" || root.errorText !== "" || root.saving || root.dirty
        text: root.errorText !== ""
          ? root.errorText
          : (root.saving || root.dirty ? root.t("schema.saving") : root.statusText)
        color: root.errorText !== "" ? Commons.Color.urgent : Qt.darker(root.foreground, 1.3)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  Component.onCompleted: refresh()
}
