import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  property var strings: null
  property string pluginDir: ""
  property string sectionId: ""
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family

  property var schema: ({})
  property var values: ({})
  property bool loaded: false
  property bool dirty: false
  property bool saving: false
  property bool pendingApply: false
  property string statusText: ""
  property string errorText: ""
  property int applyDebounceMs: 350

  function t(key) { return strings ? strings.t(key) : key }

  function markDirty() {
    if (!loaded) return
    dirty = true
    errorText = ""
    statusText = ""
    applyTimer.restart()
  }

  function expandPath(p) {
    var s = String(p || "")
    if (s.indexOf("~/") === 0)
      return Quickshell.env("HOME") + s.slice(1)
    return s
  }

  function loadSchema(text) {
    try { schema = JSON.parse(text || "{}") || {} } catch (e) { schema = {} }
  }

  function loadValues(text) {
    var data = {}
    try { data = JSON.parse(text || "{}") || {} } catch (e) { data = {} }
    // Don't clobber in-progress edits.
    if (dirty || saving || pendingApply) return
    values = data
    dirty = false
    loaded = true
    errorText = ""
  }

  function reload() {
    if (!sectionId) return
    loaded = false
    applyTimer.stop()
    pendingApply = false
    dirty = false
    schemaProc.command = ["python3", pluginDir + "/bin/settings", "schema", sectionId]
    valuesProc.command = ["python3", pluginDir + "/bin/settings", "get", sectionId]
    schemaProc.running = false
    valuesProc.running = false
    schemaProc.running = true
    valuesProc.running = true
  }

  function apply() {
    if (!loaded) {
      diagApply("skipped", "not-loaded")
      return
    }
    if (saving) {
      pendingApply = true
      diagApply("skipped", "busy")
      return
    }
    if (!dirty) return
    saving = true
    pendingApply = false
    statusText = t("schema.saving")
    errorText = ""
    // Capture payload, then clear dirty so edits during save re-dirty + requeue.
    var payload = JSON.stringify(values)
    dirty = false
    diagApply("start", "", payload)
    setProc.command = ["python3", pluginDir + "/bin/settings", "set", sectionId, payload]
    setProc.running = false
    setProc.running = true
  }

  function diagApply(status, error, payload) {
    diagProc.command = [
      "python3", pluginDir + "/bin/diag-apply",
      sectionId, status, String(error || ""),
      payload !== undefined && payload !== null ? String(payload) : ""
    ]
    diagProc.running = false
    diagProc.running = true
  }

  function openEditor(path) {
    Quickshell.execDetached(["omarchy-launch-config-editor", expandPath(path)])
  }

  Timer {
    id: applyTimer
    interval: root.applyDebounceMs
    repeat: false
    onTriggered: root.apply()
  }

  Process {
    id: schemaProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadSchema(text)
    }
    stderr: StdioCollector { waitForEnd: true }
  }

  Process {
    id: valuesProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadValues(text)
    }
    stderr: StdioCollector { id: getErr; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0)
        root.errorText = String(getErr.text || "").trim() || root.t("schema.error")
      else if (!root.loaded)
        root.loaded = true
    }
  }

  Process {
    id: setProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: setErr; waitForEnd: true }
    onExited: function(code) {
      root.saving = false
      if (code === 0) {
        root.statusText = root.t("schema.saved")
        root.diagApply("ok", "", JSON.stringify(root.values))
        // No full reload — keeps focus/text caret and avoids fighting live edits.
        if (root.dirty || root.pendingApply) {
          root.pendingApply = false
          root.dirty = true
          root.applyTimer.restart()
        }
      } else {
        var err = String(setErr.text || "").trim() || root.t("schema.error")
        root.errorText = err
        root.dirty = true
        root.diagApply("error", err, JSON.stringify(root.values))
      }
    }
  }

  Process {
    id: diagProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
  }

  Flickable {
    anchors.fill: parent
    contentWidth: width
    contentHeight: col.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
      id: col
      width: parent.width
      spacing: Style.spacing.md

      SchemaForm {
        Layout.fillWidth: true
        strings: root.strings
        schema: root.schema
        values: root.values
        loaded: root.loaded
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onFieldChanged: function(key, value) {
          var next = Object.assign({}, root.values || {})
          next[key] = value
          root.values = next
          root.markDirty()
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.md

        Repeater {
          model: root.schema.editors || []
          delegate: Button {
            required property var modelData
            text: root.t(modelData.labelKey || "schema.openEditor")
            bordered: true
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: root.openEditor(modelData.path)
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
  }

  onSectionIdChanged: if (pluginDir) reload()
  Component.onCompleted: if (sectionId && pluginDir) reload()
}
