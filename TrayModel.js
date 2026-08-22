var SECTIONS = ["left", "center", "right"]

function text(value) {
  return String(value || "").toLowerCase()
}

function itemNamed(item, name) {
  if (!item) return false
  return text(item.id).indexOf(name) !== -1
    || text(item.title).indexOf(name) !== -1
    || text(item.tooltipTitle).indexOf(name) !== -1
}

function entryId(entry) {
  if (typeof entry === "string") return entry
  if (entry && typeof entry === "object" && !Array.isArray(entry)) {
    var id = entry.id
    if (id !== undefined && id !== null && String(id) !== "") return String(id)
  }
  return ""
}

function entrySettings(entry) {
  if (!entry || typeof entry !== "object" || Array.isArray(entry)) return {}
  var copy = {}
  for (var key in entry) {
    if (key === "id") continue
    copy[key] = entry[key]
  }
  return copy
}

function layoutHasWidget(layout, id) {
  for (var s = 0; s < SECTIONS.length; s++) {
    var entries = layout && layout[SECTIONS[s]]
    if (!Array.isArray(entries)) continue
    for (var i = 0; i < entries.length; i++) {
      if (entryId(entries[i]) === id) return true
    }
  }
  return false
}

// LocalSend's item shows no state, offers only Open and Quit, and its primary
// click is a no-op, so Share > Receive is the whole surface. Hiding it by hand
// doesn't stick either: LocalSend picks a fresh tray id every launch.
function ownedByOmarchy(item, layout) {
  return itemNamed(item, "localsend")
    || (layoutHasWidget(layout, "omarchy.dropbox") && itemNamed(item, "dropbox"))
}

// QML can hand a settings array across property boundaries as a variant-list
// proxy: typeof "object", instanceof Array, but Array.isArray false and array
// methods missing. Which form arrives depends on the injection path, so every
// settings-derived list must be copied into a real array before use.
function asList(value) {
  if (Array.isArray(value)) return value
  if (value && typeof value === "object" && typeof value.length === "number") {
    var out = []
    for (var i = 0; i < value.length; i++) out.push(value[i])
    return out
  }
  return []
}

// The `widgets` setting holds one wrapper per captured bar widget:
//   { entry: <original layout entry>, from: <section it came from> }
// Tolerate hand-edited shorthand (a bare id string, or a bare entry object)
// so a typo'd shell.json degrades to defaults instead of a dead tray.
function normalizeWrappers(raw) {
  var out = []
  var values = asList(raw)
  for (var i = 0; i < values.length; i++) {
    var wrapper = values[i]
    if (!wrapper) continue
    if (typeof wrapper === "string") {
      out.push({ entry: { id: wrapper }, from: "right" })
      continue
    }
    if (wrapper.entry && entryId(wrapper.entry)) {
      var from = SECTIONS.indexOf(wrapper.from) !== -1 ? wrapper.from : "right"
      out.push({ entry: wrapper.entry, from: from })
      continue
    }
    if (entryId(wrapper)) out.push({ entry: wrapper, from: "right" })
  }
  return out
}

function wrapperId(wrapper) {
  if (!wrapper) return ""
  return wrapper.entry ? entryId(wrapper.entry) : entryId(wrapper)
}

function findLayoutEntry(layout, id) {
  for (var s = 0; s < SECTIONS.length; s++) {
    var entries = layout ? layout[SECTIONS[s]] : null
    if (!Array.isArray(entries)) continue
    for (var i = 0; i < entries.length; i++) {
      if (entryId(entries[i]) === id) {
        return { section: SECTIONS[s], entries: entries, index: i, entry: entries[i] }
      }
    }
  }
  return null
}

// Mutates `config` in place: pull `sourceId`'s entry out of the bar layout
// and append it to the tray entry's `widgets` list, remembering the section
// and index it came from so a restore can put it back. The capture runs
// deferred, after the bar's own drop may have reshuffled the entry, so the
// caller passes the section/index observed at drag start; the entry's
// current position is only a fallback. Returns true when anything moved.
function captureIntoTray(config, trayId, sourceId, fromRegion, fromIndex) {
  if (!sourceId || sourceId === trayId) return false
  var layout = config && config.bar ? config.bar.layout : null
  if (!layout) return false

  var source = findLayoutEntry(layout, sourceId)
  if (!source) return false
  source.entries.splice(source.index, 1)

  // Resolve the tray entry only after the splice: both can live in the same
  // section array, and an index recorded before the removal would be stale.
  var tray = findLayoutEntry(layout, trayId)
  if (!tray) {
    source.entries.splice(source.index, 0, source.entry)
    return false
  }

  var trayEntry = tray.entry
  if (typeof trayEntry === "string") {
    trayEntry = { id: trayEntry }
    tray.entries[tray.index] = trayEntry
  }
  if (!Array.isArray(trayEntry.widgets)) trayEntry.widgets = []
  var entry = typeof source.entry === "string" ? { id: source.entry } : source.entry
  var from = SECTIONS.indexOf(fromRegion) !== -1 ? fromRegion : source.section
  var at = typeof fromIndex === "number" && fromIndex >= 0 ? fromIndex : source.index
  trayEntry.widgets.push({ entry: entry, from: from, at: at })
  return true
}

// Remove `widgetId`'s wrapper from a tray entry (widgets + pinnedWidgets)
// and return it, or null when it isn't hosted there.
function takeWrapper(trayEntry, widgetId) {
  var wrappers = Array.isArray(trayEntry.widgets) ? trayEntry.widgets : []
  var index = -1
  for (var i = 0; i < wrappers.length; i++) {
    if (wrapperId(wrappers[i]) === widgetId) { index = i; break }
  }
  if (index === -1) return null
  var wrapper = wrappers.splice(index, 1)[0]
  if (wrappers.length === 0) delete trayEntry.widgets
  if (Array.isArray(trayEntry.pinnedWidgets)) {
    trayEntry.pinnedWidgets = trayEntry.pinnedWidgets.filter(function(id) { return id !== widgetId })
    if (trayEntry.pinnedWidgets.length === 0) delete trayEntry.pinnedWidgets
  }
  return wrapper
}

function indexOfEntry(entries, id) {
  for (var i = 0; i < entries.length; i++) {
    if (entryId(entries[i]) === id) return i
  }
  return -1
}

// Mutates `config` in place: take `widgetId` out of the tray's `widgets` list
// and put its entry back into the bar layout, next to the tray when they share
// a section, otherwise at the inner edge of the section it came from.
function restoreFromTray(config, trayId, widgetId) {
  var layout = config && config.bar ? config.bar.layout : null
  if (!layout) return false

  var tray = findLayoutEntry(layout, trayId)
  if (!tray || typeof tray.entry === "string") return false
  var wrapper = takeWrapper(tray.entry, widgetId)
  if (!wrapper) return false

  var entry = wrapper && wrapper.entry ? wrapper.entry : wrapper
  var from = wrapper && SECTIONS.indexOf(wrapper.from) !== -1 ? wrapper.from : "right"
  if (!Array.isArray(layout[from])) layout[from] = []
  var target = layout[from]
  // Best effort back to where it was captured from: the recorded index, when
  // one was recorded and still fits; otherwise beside the tray or at the
  // section's inner edge.
  var at = wrapper && typeof wrapper.at === "number" && wrapper.at >= 0 ? Math.min(Math.round(wrapper.at), target.length) : -1
  if (at !== -1) target.splice(at, 0, entry)
  else if (from === tray.section) target.splice(tray.index + 1, 0, entry)
  else if (from === "right") target.unshift(entry)
  else target.push(entry)
  return true
}

// Drop a hosted widget back into the bar layout at an explicit position —
// the drag-out counterpart of captureIntoTray. Inserts before `beforeName`
// in `toRegion`, or at the section's end when beforeName is empty or gone.
function dragOutOfTray(config, trayId, widgetId, toRegion, beforeName) {
  var layout = config && config.bar ? config.bar.layout : null
  if (!layout) return false

  var tray = findLayoutEntry(layout, trayId)
  if (!tray || typeof tray.entry === "string") return false
  var wrapper = takeWrapper(tray.entry, widgetId)
  if (!wrapper) return false

  var entry = wrapper && wrapper.entry ? wrapper.entry : wrapper
  var region = SECTIONS.indexOf(toRegion) !== -1 ? toRegion : "right"
  if (!Array.isArray(layout[region])) layout[region] = []
  var target = layout[region]
  var index = beforeName ? indexOfEntry(target, String(beforeName)) : -1
  if (index < 0) target.push(entry)
  else target.splice(index, 0, entry)
  return true
}

if (typeof module !== "undefined") {
  module.exports = {
    asList: asList,
    itemNamed: itemNamed,
    entryId: entryId,
    entrySettings: entrySettings,
    layoutHasWidget: layoutHasWidget,
    ownedByOmarchy: ownedByOmarchy,
    normalizeWrappers: normalizeWrappers,
    wrapperId: wrapperId,
    findLayoutEntry: findLayoutEntry,
    captureIntoTray: captureIntoTray,
    restoreFromTray: restoreFromTray,
    dragOutOfTray: dragOutOfTray
  }
}
