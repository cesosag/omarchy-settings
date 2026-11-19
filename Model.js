.pragma library

function secondsToMinutes(seconds) {
  var n = Number(seconds)
  if (!isFinite(n) || n < 0) return 0
  return Math.round(n / 60)
}

function minutesToSeconds(minutes) {
  var n = Number(minutes)
  if (!isFinite(n) || n < 0) return 0
  return Math.round(n) * 60
}

function parseIdle(text) {
  var out = { screensaver: 150, lock: 300 }
  try {
    var data = JSON.parse(String(text || "{}")) || {}
    var idle = data.idle || {}
    if (idle.screensaver !== undefined) out.screensaver = Number(idle.screensaver) || 0
    if (idle.lock !== undefined) out.lock = Number(idle.lock) || 0
  } catch (e) {}
  return out
}

function modeLabel(width, height, refreshRate) {
  var w = Number(width) || 0
  var h = Number(height) || 0
  var hz = Number(refreshRate) || 0
  if (!w || !h) return "preferred"
  if (!hz) return w + "x" + h
  var rounded = Math.round(hz * 100) / 100
  return w + "x" + h + "@" + rounded
}

function normalizeMode(mode) {
  var value = String(mode || "").trim()
  if (!value) return "preferred"
  return value.replace(/Hz$/i, "")
}

function positionLabel(x, y) {
  return String(Number(x) || 0) + "x" + String(Number(y) || 0)
}

function scaleOptions(current) {
  var presets = ["auto", "1", "1.25", "1.5", "1.6", "1.75", "2"]
  var cur = String(current === undefined || current === null ? "" : current)
  if (cur !== "" && presets.indexOf(cur) === -1) presets.push(cur)
  var out = []
  for (var i = 0; i < presets.length; i++) {
    out.push({ value: presets[i], label: presets[i] })
  }
  return out
}

function modeOptions(availableModes, currentMode) {
  var seen = {}
  var out = [{ value: "preferred", label: "preferred" }]
  seen.preferred = true
  var modes = Array.isArray(availableModes) ? availableModes : []
  for (var i = 0; i < modes.length; i++) {
    var value = normalizeMode(modes[i])
    if (!value || seen[value]) continue
    seen[value] = true
    out.push({ value: value, label: value })
  }
  var current = normalizeMode(currentMode)
  if (current && !seen[current]) out.push({ value: current, label: current })
  return out
}

function positionOptions(current) {
  var cur = String(current || "auto")
  var out = [{ value: "auto", label: "auto" }]
  if (cur !== "auto") out.push({ value: cur, label: cur })
  return out
}

function monitorsFromHyprctl(text) {
  var parsed = []
  try { parsed = JSON.parse(String(text || "[]")) } catch (e) { return [] }
  if (!Array.isArray(parsed)) return []
  var out = []
  for (var i = 0; i < parsed.length; i++) {
    var m = parsed[i] || {}
    if (m.disabled === true) continue
    var name = String(m.name || "")
    if (!name) continue
    var mode = modeLabel(m.width, m.height, m.refreshRate)
    var scale = m.scale !== undefined && m.scale !== null ? String(m.scale) : "1"
    out.push({
      output: name,
      description: String(m.description || m.model || name),
      mode: mode,
      position: positionLabel(m.x, m.y),
      scale: scale,
      availableModes: Array.isArray(m.availableModes) ? m.availableModes.slice() : [],
      focused: !!m.focused
    })
  }
  return out
}

function monitorsPayload(monitors) {
  var list = Array.isArray(monitors) ? monitors : []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var m = list[i] || {}
    var scaleRaw = String(m.scale || "1")
    var scale = scaleRaw === "auto" ? "auto" : Number(scaleRaw)
    out.push({
      output: String(m.output || ""),
      mode: normalizeMode(m.mode) || "preferred",
      position: String(m.position || "auto"),
      scale: scaleRaw === "auto" ? "auto" : (isFinite(scale) ? scale : 1)
    })
  }
  return JSON.stringify(out)
}

function parseShell(text) {
  var out = {
    screensaver: 150,
    lock: 300,
    dockPosition: "bottom",
    dockAutohide: false,
    barPosition: "top",
    barBackground: "opaque"
  }
  try {
    var data = JSON.parse(String(text || "{}")) || {}
    var idle = data.idle || {}
    if (idle.screensaver !== undefined) out.screensaver = Number(idle.screensaver) || 0
    if (idle.lock !== undefined) out.lock = Number(idle.lock) || 0
    var dock = data.dock || {}
    if (dock.position) out.dockPosition = String(dock.position)
    out.dockAutohide = dock.autohide === true
    var bar = data.bar || {}
    if (bar.position) out.barPosition = String(bar.position)
    if (bar.background) out.barBackground = String(bar.background)
    else if (bar.transparent === true) out.barBackground = "none"
  } catch (e) {}
  return out
}
