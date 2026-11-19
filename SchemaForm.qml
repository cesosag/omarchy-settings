import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Renders a declarative schema fields[] list against a flat values object.
ColumnLayout {
  id: root

  property var strings: null
  property var schema: ({})
  property var values: ({})
  property bool loaded: false
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family

  signal fieldChanged(string key, var value)

  function t(key) { return strings ? strings.t(key) : key }

  function fieldVisible(field) {
    var when = field.visibleWhen
    if (!when || !when.key) return true
    var cur = values ? values[when.key] : undefined
    if (when.equals !== undefined) return cur === when.equals
    if (when.truthy) return !!cur
    return true
  }

  function optionList(field) {
    var opts = field.options || []
    var out = []
    for (var i = 0; i < opts.length; i++) {
      var v = opts[i]
      if (typeof v === "object") out.push(v)
      else out.push({ value: String(v), label: String(v) })
    }
    return out
  }

  function setValue(key, value) {
    // Parent owns `values`; emit only so bindings stay intact.
    fieldChanged(key, value)
  }

  function boolChecked(field) {
    var v = values ? values[field.key] : undefined
    if (field.type === "bool-int") return Number(v) > 0
    return !!v
  }

  function toggleBool(field) {
    if (field.type === "bool-int") {
      setValue(field.key, boolChecked(field) ? 0 : 1)
      return
    }
    setValue(field.key, !boolChecked(field))
  }

  function commitText(field, raw) {
    if (!loaded) return
    if (field.type === "string") {
      setValue(field.key, raw)
      return
    }
    if (raw === "" && field.nullable) {
      setValue(field.key, null)
      return
    }
    if (raw === "") return
    var n = field.type === "int" ? parseInt(raw, 10) : Number(raw)
    if (isFinite(n)) setValue(field.key, n)
  }

  spacing: Style.spacing.md

  Column {
    Layout.fillWidth: true
    spacing: Style.spacing.sm
    Text {
      textFormat: Text.PlainText
      text: root.t(root.schema.titleKey || "")
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }
    Text {
      width: parent.width
      visible: !!(root.schema.descriptionKey)
      textFormat: Text.PlainText
      text: root.t(root.schema.descriptionKey || "")
      color: Qt.darker(root.foreground, 1.35)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }
    Text {
      width: parent.width
      visible: !!(root.schema.customNoteKey) && !!(root.values && root.values.customPresent)
      textFormat: Text.PlainText
      text: root.t(root.schema.customNoteKey || "")
      color: Qt.darker(root.foreground, 1.2)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }

  Repeater {
    model: root.schema.fields || []
    delegate: Item {
      Layout.fillWidth: true
      Layout.preferredHeight: inner.implicitHeight
      visible: {
        var f = modelData
        if (!f) return false
        if (f.type === "section") return true
        return root.fieldVisible(f)
      }
      required property var modelData

      ColumnLayout {
        id: inner
        width: parent.width
        spacing: Style.spacing.sm

        PanelSectionHeader {
          visible: modelData.type === "section"
          Layout.fillWidth: true
          text: root.t(modelData.titleKey || "")
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Toggle {
          visible: modelData.type === "bool" || modelData.type === "bool-int"
          Layout.fillWidth: true
          label: root.t(modelData.labelKey || "")
          description: modelData.descriptionKey ? root.t(modelData.descriptionKey) : ""
          checked: root.boolChecked(modelData)
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          onClicked: root.toggleBool(modelData)
        }

        Dropdown {
          visible: modelData.type === "enum"
          label: root.t(modelData.labelKey || "")
          value: String((root.values && root.values[modelData.key]) || modelData.default || "")
          options: root.optionList(modelData)
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          onChanged: function(v) { root.setValue(modelData.key, v) }
        }

        Column {
          visible: modelData.type === "int" || modelData.type === "number" || modelData.type === "string"
          Layout.fillWidth: true
          spacing: Style.spacing.xs
          Text {
            textFormat: Text.PlainText
            text: root.t(modelData.labelKey || "")
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          TextField {
            width: (modelData.type === "string") ? parent.width : Style.spacing.numberFieldWidth * 1.6
            text: {
              var v = root.values ? root.values[modelData.key] : undefined
              if (v === null || v === undefined) return ""
              return String(v)
            }
            placeholderText: String(modelData.placeholder || "")
            foreground: root.foreground
            accent: root.accent
            // Commit on user edit so auto-apply sees live values (not only on blur).
            onTextEdited: root.commitText(modelData, text)
            onEditingFinished: root.commitText(modelData, text)
          }
        }
      }
    }
  }
}
