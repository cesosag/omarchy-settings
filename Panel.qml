import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Schema-driven settings panel.
//   omarchy-shell shell summon cesosag.settings 'shell'
//   omarchy-shell shell summon cesosag.settings '{"section":"input"}'
// Enable/disable whole GUI + menu wiring:
//   python3 ~/.config/omarchy/plugins/cesosag.settings/bin/settings enable|disable
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool closingFromHost: false
  property string section: "shell"
  property int sectionIndex: 0
  property bool opened: false

  property var catalog: ({ sections: [] })
  property var sectionIds: []
  // Survives the async schemas/index load so cold summon does not collapse to shell.
  property string pendingSection: ""

  // Must match schemas/index.json order — used before catalogProc finishes.
  readonly property var fallbackSectionIds: ["shell", "monitors", "input", "keybindings", "hyprland", "hyprsunset", "xdph"]

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/+$/, "")
  readonly property color foreground: Commons.Color.foreground
  readonly property color background: Commons.Color.background
  readonly property color accent: Commons.Color.accent
  readonly property string fontFamily: Style.font.family
  // Qt treats the generic family "monospace" without Nerd Font PUA glyphs.
  // Prefer Style's fc-match result; never fall back to the generic alias for icons.
  readonly property string iconFontFamily: {
    var resolved = String(Style.font.resolvedFamily || "").trim()
    if (resolved !== "" && resolved !== "monospace")
      return resolved
    return "JetBrainsMono Nerd Font"
  }

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  // Hardcoded UTF-16 escapes so icons don't depend on JSON / source encoding.
  function navIcon(id) {
    var map = {
      "shell": "\uDB81\uDCB2",       // nf-md-sleep
      "monitors": "\uDB80\uDF79",    // nf-md-monitor
      "input": "\uEFBA",             // nf-fa-fingerprint-ish / input
      "keybindings": "\uF11C",       // nf-fa-keyboard
      "hyprland": "\uF359",          // nf-linux-hyprland
      "hyprsunset": "\uF185",        // nf-fa-sun
      "xdph": "\uDB83\uDE51"         // nf-md-cast
    }
    return map[id] || ""
  }

  function knownIds() {
    return sectionIds.length ? sectionIds : fallbackSectionIds
  }

  function normalizeSection(name) {
    var value = String(name || "")
    if (value === "idle") value = "shell"
    if (!value) value = "shell"
    var ids = knownIds()
    if (ids.indexOf(value) >= 0) return value
    return ids[0]
  }

  function sectionIndexFor(name) {
    var idx = knownIds().indexOf(normalizeSection(name))
    return idx >= 0 ? idx : 0
  }

  function recordOpen(requested, resolved) {
    diagProc.command = [
      "python3", pluginDir + "/bin/diag-open",
      String(requested), String(resolved),
      String(sectionIndexFor(resolved)),
      sectionIds.length ? "1" : "0"
    ]
    diagProc.running = false
    diagProc.running = true
  }

  function open(payloadJson) {
    closingFromHost = false
    var raw = String(payloadJson || "").trim()
    var requested = "shell"
    if (raw.charAt(0) === "{") {
      try {
        var payload = JSON.parse(raw) || {}
        requested = String(payload.section || "shell")
      } catch (e) {
        requested = "shell"
      }
    } else if (raw !== "") {
      requested = raw
    }
    pendingSection = requested
    var resolved = normalizeSection(requested)
    section = resolved
    sectionIndex = sectionIndexFor(resolved)
    recordOpen(requested, resolved)
    opened = true
    window.visible = true
    Qt.callLater(function() {
      refreshSection(root.section)
      keyScope.forceActiveFocus()
    })
  }

  function close() {
    closingFromHost = true
    opened = false
    window.visible = false
    closingFromHost = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function")
      shell.hide((manifest && manifest.id) || "cesosag.settings")
    else close()
  }

  function pageFor(id) {
    var resolved = normalizeSection(id)
    if (resolved === "monitors") return monitorsPage
    if (resolved === "input") return inputPage
    if (resolved === "keybindings") return keybindingsPage
    if (resolved === "hyprland") return hyprlandPage
    if (resolved === "hyprsunset") return hyprsunsetPage
    if (resolved === "xdph") return xdphPage
    return shellPage
  }

  function refreshSection(id) {
    var page = pageFor(id)
    if (page && typeof page.reload === "function") page.reload()
    else if (page && typeof page.refresh === "function") page.refresh()
  }

  function selectSection(id) {
    pendingSection = id
    var requested = normalizeSection(id)
    section = requested
    sectionIndex = sectionIndexFor(requested)
    recordOpen(id, requested)
    refreshSection(requested)
  }

  function loadCatalog(text) {
    var data = {}
    try { data = JSON.parse(text || "{}") || {} } catch (e) { data = {} }
    catalog = data
    var ids = []
    var sections = data.sections || []
    for (var i = 0; i < sections.length; i++) {
      if (sections[i] && sections[i].id) ids.push(sections[i].id)
    }
    sectionIds = ids
    var target = pendingSection !== "" ? pendingSection : section
    var resolved = normalizeSection(target)
    section = resolved
    sectionIndex = sectionIndexFor(resolved)
    if (opened) refreshSection(resolved)
  }

  // Load catalog as UTF-8 from disk (avoid Process JSON ascii-escaping of icons).
  FileView {
    id: catalogFile
    path: root.pluginDir + "/schemas/index.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadCatalog(text())
    onFileChanged: reload()
    onLoadFailed: root.loadCatalog("{}")
  }

  Process {
    id: diagProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
  }

  // After `omarchy plugin add --enable`, Setup still opens editors until menu
  // overrides are merged. Ensure once when the panel first loads.
  Process {
    id: ensureProc
    command: ["python3", root.pluginDir + "/bin/settings", "ensure"]
    running: true
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
  }

  FloatingWindow {
    id: window
    title: strings.t("window.title") + " — " + root.section
    color: root.background
    implicitWidth: 780
    implicitHeight: 640
    minimumSize: Qt.size(600, 480)

    onVisibleChanged: {
      root.opened = visible
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide((root.manifest && root.manifest.id) || "cesosag.settings")
    }

    FocusScope {
      id: keyScope
      anchors.fill: parent
      focus: true

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.requestClose()
          event.accepted = true
        }
      }

      RowLayout {
        anchors.fill: parent
        anchors.margins: Style.space(18)
        spacing: Style.spacing.xl

        Column {
          Layout.preferredWidth: Style.space(168)
          Layout.fillHeight: true
          spacing: Style.spacing.sm

          Text {
            textFormat: Text.PlainText
            text: strings.t("window.title")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Item { height: Style.spacing.md; width: 1 }

          Repeater {
            model: {
              var secs = root.catalog.sections || []
              if (secs.length) return secs
              return [
                { id: "shell", navKey: "nav.shell" },
                { id: "monitors", navKey: "nav.monitors" },
                { id: "input", navKey: "nav.input" },
                { id: "keybindings", navKey: "nav.keybindings" },
                { id: "hyprland", navKey: "nav.hyprland" },
                { id: "hyprsunset", navKey: "nav.hyprsunset" },
                { id: "xdph", navKey: "nav.xdph" }
              ]
            }
            delegate: Button {
              required property var modelData
              width: Style.space(168)
              text: strings.t(modelData.navKey || modelData.id)
              iconText: root.navIcon(modelData.id)
              bordered: true
              selected: root.section === modelData.id
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.iconFontFamily
              leftAlign: true
              onClicked: root.selectSection(modelData.id)
            }
          }
        }

        Rectangle {
          Layout.fillHeight: true
          Layout.preferredWidth: 1
          width: 1
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
        }

        StackLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          currentIndex: root.sectionIndex

          SchemaPage {
            id: shellPage
            strings: strings
            pluginDir: root.pluginDir
            sectionId: "shell"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
          }
          MonitorsPage {
            id: monitorsPage
            strings: strings
            pluginDir: root.pluginDir
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
          }
          SchemaPage {
            id: inputPage
            strings: strings
            pluginDir: root.pluginDir
            sectionId: "input"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
          }
          KeybindingsPage {
            id: keybindingsPage
            strings: strings
            pluginDir: root.pluginDir
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
          }
          SchemaPage {
            id: hyprlandPage
            strings: strings
            pluginDir: root.pluginDir
            sectionId: "hyprland"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
          }
          SchemaPage {
            id: hyprsunsetPage
            strings: strings
            pluginDir: root.pluginDir
            sectionId: "hyprsunset"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
          }
          SchemaPage {
            id: xdphPage
            strings: strings
            pluginDir: root.pluginDir
            sectionId: "xdph"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
          }
        }
      }
    }
  }
}
