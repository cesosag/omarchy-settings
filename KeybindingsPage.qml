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
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family

  property var items: []
  property string filterText: ""
  property string filterMode: "all"
  property int expandedIndex: -1
  property bool dirty: false
  property bool saving: false
  property bool pendingApply: false
  property bool loaded: false
  property string statusText: ""
  property string errorText: ""

  readonly property string bindingsPath: Quickshell.env("HOME") + "/.config/hypr/bindings.lua"
  readonly property var filterOptions: [
    { value: "all", label: "All" },
    { value: "modified", label: "Modified" },
    { value: "custom", label: "Custom" }
  ]

  readonly property var filteredItems: {
    var q = String(filterText || "").trim().toLowerCase()
    var mode = String(filterMode || "all")
    var src = Array.isArray(items) ? items : []
    var out = []
    for (var i = 0; i < src.length; i++) {
      var row = src[i] || {}
      var status = String(row.status || "default")
      if (mode === "modified" && status !== "rebound" && status !== "unbound") continue
      if (mode === "custom" && status !== "custom") continue
      if (q) {
        var hay = (String(row.keys || "") + " " + String(row.label || "") + " " + String(row.arg || "")).toLowerCase()
        if (hay.indexOf(q) < 0) continue
      }
      out.push({ item: row, index: i })
    }
    return out
  }

  function t(key) { return strings ? strings.t(key) : key }

  function markDirty() {
    if (!loaded) return
    dirty = true
    statusText = ""
    errorText = ""
    applyTimer.restart()
  }

  function statusLabel(status) {
    if (status === "rebound") return t("keybindings.statusRebound")
    if (status === "unbound") return t("keybindings.statusUnbound")
    if (status === "custom") return t("keybindings.statusCustom")
    return t("keybindings.statusDefault")
  }

  function loadFromJson(text) {
    if (dirty || saving || pendingApply) {
      loaded = true
      return
    }
    var data = {}
    try { data = JSON.parse(text || "{}") || {} } catch (e) { data = {} }
    items = Array.isArray(data.items) ? data.items : []
    expandedIndex = -1
    dirty = false
    loaded = true
    errorText = ""
  }

  function reload() {
    loaded = false
    applyTimer.stop()
    getProc.running = false
    getProc.running = true
  }

  function updateItem(index, patch) {
    var next = items.slice()
    var row = Object.assign({}, next[index] || {})
    for (var k in patch) row[k] = patch[k]
    next[index] = row
    items = next
    markDirty()
  }

  function commitKeys(index, text, isCustom, rowStatus, row) {
    var patch = { keys: text }
    if (!isCustom && rowStatus === "default" && text !== String(row.originalKeys || ""))
      patch.status = "rebound"
    else if (!isCustom && rowStatus !== "unbound")
      patch.status = (text !== String(row.originalKeys || "")) ? "rebound" : rowStatus
    updateItem(index, patch)
  }

  function setStatus(index, status) {
    var row = items[index] || {}
    var patch = { status: status }
    if (status === "default") {
      patch.keys = row.originalKeys || row.keys
    } else if (status === "rebound" && !row.keys) {
      patch.keys = row.originalKeys || ""
    }
    updateItem(index, patch)
  }

  function addCustom() {
    var sep = String.fromCharCode(31)
    items = items.concat([{
      id: "custom" + sep + "SUPER + " + sep,
      originalKeys: "SUPER + ",
      keys: "SUPER + ",
      label: "",
      allKeys: "SUPER + ",
      dispatcher: "exec",
      arg: "",
      status: "custom"
    }])
    expandedIndex = items.length - 1
    markDirty()
  }

  function removeCustom(index) {
    var row = items[index] || {}
    if (String(row.status) !== "custom") return
    items = items.filter(function(_, i) { return i !== index })
    if (expandedIndex === index) expandedIndex = -1
    else if (expandedIndex > index) expandedIndex -= 1
    markDirty()
  }

  function apply() {
    if (saving) {
      pendingApply = true
      return
    }
    if (!dirty || !loaded) return
    saving = true
    pendingApply = false
    statusText = t("schema.saving")
    errorText = ""
    var payload = JSON.stringify({ items: items })
    dirty = false
    setProc.command = ["python3", pluginDir + "/bin/lua-settings", "set", "bindings-catalog", payload]
    setProc.running = false
    setProc.running = true
  }

  Timer {
    id: applyTimer
    interval: 650
    repeat: false
    onTriggered: root.apply()
  }

  function openEditor() {
    Quickshell.execDetached(["omarchy-launch-config-editor", bindingsPath])
  }

  Process {
    id: getProc
    command: ["python3", root.pluginDir + "/bin/lua-settings", "get", "bindings-catalog"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadFromJson(text)
    }
    stderr: StdioCollector { id: getErr; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) root.errorText = String(getErr.text || "").trim() || root.t("keybindings.error")
    }
  }

  Process {
    id: setProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: setErr; waitForEnd: true }
    onExited: function(code) {
      root.saving = false
      if (code === 0) {
        root.statusText = root.t("keybindings.saved")
        if (root.dirty || root.pendingApply) {
          root.pendingApply = false
          root.dirty = true
          root.applyTimer.restart()
        }
      } else {
        root.dirty = true
        root.errorText = String(setErr.text || "").trim() || root.t("keybindings.error")
      }
    }
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.spacing.md

    Column {
      Layout.fillWidth: true
      spacing: Style.spacing.sm
      Text {
        textFormat: Text.PlainText
        text: root.t("keybindings.title")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.t("keybindings.description")
        color: Qt.darker(root.foreground, 1.35)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.md
      TextField {
        Layout.fillWidth: true
        text: root.filterText
        placeholderText: root.t("keybindings.search")
        foreground: root.foreground
        accent: root.accent
        onTextChanged: root.filterText = text
      }
      Dropdown {
        label: ""
        value: root.filterMode
        options: root.filterOptions
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onChanged: function(v) { root.filterMode = v }
      }
    }

    Text {
      Layout.fillWidth: true
      textFormat: Text.PlainText
      text: root.t("keybindings.count").replace("%1", String(root.filteredItems.length)).replace("%2", String(root.items.length))
      color: Qt.darker(root.foreground, 1.35)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }

    Flickable {
      Layout.fillWidth: true
      Layout.fillHeight: true
      contentWidth: width
      contentHeight: listCol.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: listCol
        width: parent.width
        spacing: Style.spacing.sm

        Text {
          visible: root.filteredItems.length === 0
          width: parent.width
          textFormat: Text.PlainText
          text: root.loaded ? root.t("keybindings.empty") : root.t("keybindings.loading")
          color: Qt.darker(root.foreground, 1.3)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Repeater {
          model: root.filteredItems
          delegate: Column {
            width: listCol.width
            spacing: Style.spacing.xs
            required property var modelData
            required property int index

            readonly property var row: modelData.item || {}
            readonly property int itemIndex: modelData.index
            readonly property string rowStatus: String(row.status || "default")
            readonly property bool isExpanded: root.expandedIndex === itemIndex
            readonly property bool isCustom: rowStatus === "custom"
            readonly property bool isModified: rowStatus === "rebound" || rowStatus === "unbound"

            Rectangle {
              width: parent.width
              height: headerRow.implicitHeight + Style.spacing.sm * 2
              color: isExpanded ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.08) : "transparent"
              radius: 4

              RowLayout {
                id: headerRow
                anchors.fill: parent
                anchors.margins: Style.spacing.sm
                spacing: Style.spacing.sm

                Column {
                  Layout.fillWidth: true
                  spacing: 2
                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: String(row.label || row.arg || "(unnamed)")
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: (rowStatus === "unbound" ? "∅ " : "") + String(row.keys || "")
                      + (isModified && row.originalKeys && row.keys !== row.originalKeys
                         ? "  ←  " + String(row.originalKeys) : "")
                    color: rowStatus === "unbound" ? Commons.Color.urgent : Qt.darker(root.foreground, 1.35)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.statusLabel(rowStatus)
                  color: isModified || isCustom ? root.accent : Qt.darker(root.foreground, 1.5)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Button {
                  text: isExpanded ? root.t("keybindings.collapse") : root.t("keybindings.edit")
                  bordered: true
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  onClicked: root.expandedIndex = isExpanded ? -1 : itemIndex
                }
              }
            }

            Column {
              width: parent.width
              visible: isExpanded
              spacing: Style.spacing.sm
              leftPadding: Style.spacing.sm
              rightPadding: Style.spacing.sm

              Column {
                width: parent.width
                spacing: Style.spacing.xs
                Text {
                  textFormat: Text.PlainText
                  text: root.t("keybindings.keys")
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                TextField {
                  width: parent.width
                  text: String(row.keys || "")
                  enabled: rowStatus !== "unbound"
                  placeholderText: "SUPER + SHIFT + R"
                  foreground: root.foreground
                  accent: root.accent
                  onTextEdited: root.commitKeys(itemIndex, text, isCustom, rowStatus, row)
                  onEditingFinished: root.commitKeys(itemIndex, text, isCustom, rowStatus, row)
                }
              }

              Column {
                width: parent.width
                visible: isCustom || rowStatus === "rebound"
                spacing: Style.spacing.xs
                Text {
                  textFormat: Text.PlainText
                  text: root.t("keybindings.label")
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                TextField {
                  width: parent.width
                  text: String(row.label || "")
                  placeholderText: root.t("keybindings.labelPlaceholder")
                  foreground: root.foreground
                  accent: root.accent
                  onTextEdited: root.updateItem(itemIndex, { label: text })
                  onEditingFinished: root.updateItem(itemIndex, { label: text })
                }
              }

              Column {
                width: parent.width
                visible: isCustom
                spacing: Style.spacing.xs
                Text {
                  textFormat: Text.PlainText
                  text: root.t("keybindings.command")
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                TextField {
                  width: parent.width
                  text: String(row.arg || "")
                  placeholderText: "foot"
                  foreground: root.foreground
                  accent: root.accent
                  onTextEdited: root.updateItem(itemIndex, { arg: text })
                  onEditingFinished: root.updateItem(itemIndex, { arg: text })
                }
              }

              Text {
                width: parent.width
                visible: !isCustom && String(row.arg || "") !== ""
                textFormat: Text.PlainText
                text: root.t("keybindings.action") + ": " + String(row.dispatcher || "") + " " + String(row.arg || "")
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WrapAnywhere
              }

              Flow {
                width: parent.width
                spacing: Style.spacing.sm

                Button {
                  visible: !isCustom && rowStatus !== "rebound"
                  text: root.t("keybindings.rebind")
                  bordered: true
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  onClicked: root.setStatus(itemIndex, "rebound")
                }
                Button {
                  visible: !isCustom && rowStatus !== "unbound"
                  text: root.t("keybindings.unbind")
                  bordered: true
                  foreground: root.foreground
                  accent: Commons.Color.urgent
                  fontFamily: root.fontFamily
                  onClicked: root.setStatus(itemIndex, "unbound")
                }
                Button {
                  visible: !isCustom && (rowStatus === "rebound" || rowStatus === "unbound")
                  text: root.t("keybindings.restore")
                  bordered: true
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  onClicked: root.setStatus(itemIndex, "default")
                }
                Button {
                  visible: isCustom
                  text: root.t("keybindings.remove")
                  bordered: true
                  foreground: root.foreground
                  accent: Commons.Color.urgent
                  fontFamily: root.fontFamily
                  onClicked: root.removeCustom(itemIndex)
                }
              }
            }

            PanelSeparator {
              width: parent.width
              visible: index < root.filteredItems.length - 1
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
        text: root.t("keybindings.add")
        bordered: true
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onClicked: root.addCustom()
      }
      Button {
        text: root.t("keybindings.openEditor")
        bordered: true
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onClicked: root.openEditor()
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

  Component.onCompleted: reload()
}
