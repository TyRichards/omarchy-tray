import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell.Services.SystemTray
import qs.Commons
import qs.Ui
import "TrayModel.js" as TrayModel

// A drop-in replacement for omarchy.tray. Everything the stock tray does —
// status notifier icons, pin/hide, the slide-out drawer, in-popup app menus —
// plus: any bar widget (clock, workspaces, weather, menu, panels, custom
// modules...) can be dragged onto this tray and it moves inside the drawer.
// Captured widgets keep their settings, clicks, tooltips, and panels; they can
// be pinned (always visible) or restored to the bar from the right-click
// manage popup.
BarWidget {
  id: root
  moduleName: "io.github.tyrichards.tray"

  property bool expanded: false
  property bool managePopupOpen: false
  property bool trayMenuOpen: false
  property var activeTrayItem: null
  property var activeTrayAnchor: null
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var pinnedIds: TrayModel.asList(settings.pinned).map(String)
  readonly property var hiddenIds: TrayModel.asList(settings.hidden).map(String)
  readonly property var pinnedItems: bucket("pinned")
  readonly property var drawerItems: bucket("drawer")
  readonly property var allItems: bucket("all")
  readonly property int drawerCount: drawerItems.length
  readonly property int trayItemExtent: Style.bar.iconSlot

  // Bar widgets captured into the drawer, and which of them are pinned
  // (always visible, outside the drawer). Stored on this widget's own
  // shell.json entry so they survive restarts and sync across monitors.
  readonly property var hostedWrappers: TrayModel.normalizeWrappers(settings.widgets)
  readonly property var pinnedWidgetIds: TrayModel.asList(settings.pinnedWidgets).map(String)
  readonly property var hostedPinned: hostedWrappers.filter(function(wrapper) {
    return root.pinnedWidgetIds.indexOf(TrayModel.wrapperId(wrapper)) !== -1
  })
  readonly property var hostedDrawer: hostedWrappers.filter(function(wrapper) {
    return root.pinnedWidgetIds.indexOf(TrayModel.wrapperId(wrapper)) === -1
  })
  readonly property bool hasDrawerContent: drawerCount > 0 || hostedDrawer.length > 0

  // Match Waybar's group/tray-expander drawer transition-duration.
  readonly property int animationDuration: 600
  property real revealProgress: (expanded || dragOver) ? 1 : 0

  Behavior on revealProgress {
    NumberAnimation { duration: root.animationDuration; easing.type: Easing.OutCubic }
  }

  // ---------------------------------------------------------------------------
  // Drag-into-tray. The bar host tracks every widget drag globally
  // (barDragSource + barDragSceneX/Y). Watch that state: while a drag from
  // another widget hovers over this tray, highlight and hold the drawer open;
  // when it is released here, capture the widget into the drawer.
  // ---------------------------------------------------------------------------

  readonly property bool dragActive: root.bar ? dragEligible(root.bar.barDragSource) : false
  property bool dragOver: false
  property string dragSourceId: ""
  property string dragSourceRegion: ""
  property int dragSourceIndex: -1

  // Imperative on purpose: the drag-start handler runs inside the very signal
  // dispatch that dirtied the dragActive binding, and reading the binding
  // there can return a stale false. Recomputing from the live properties is
  // always current.
  function dragEligible(slot) {
    if (!slot || !root.bar) return false
    if (String(slot.moduleName || "") === root.moduleName) return false
    var win = root.QsWindow ? root.QsWindow.window : null
    return !!win && root.bar.barDragWindow === win
  }

  function updateDragOver() {
    if (!dragEligible(root.bar ? root.bar.barDragSource : null)) {
      dragOver = false
      return
    }
    var origin
    try {
      origin = root.mapToItem(null, 0, 0)
    } catch (e) {
      dragOver = false
      return
    }
    var x = root.bar.barDragSceneX
    var y = root.bar.barDragSceneY
    dragOver = x >= origin.x && x <= origin.x + root.width
      && y >= origin.y && y <= origin.y + root.height
  }

  Connections {
    target: root.bar
    ignoreUnknownSignals: true

    function onBarDragSourceChanged() {
      var slot = root.bar.barDragSource
      if (slot) {
        // Only the instance living in the drag's own bar window can win the
        // drop; every other monitor's copy keeps an empty id and stays inert.
        var eligible = root.dragEligible(slot)
        root.dragSourceId = eligible ? String(slot.moduleName || "") : ""
        root.dragSourceRegion = String(slot.region || "")
        // Remember where the widget started so a later Restore can put it
        // back exactly, even though the bar's own drop may reshuffle it
        // before the deferred capture runs.
        root.dragSourceIndex = -1
        if (eligible && typeof root.bar.layoutEntries === "function") {
          var entries = root.bar.layoutEntries(root.dragSourceRegion)
          for (var i = 0; i < entries.length; i++) {
            if (TrayModel.entryId(entries[i]) === root.dragSourceId) {
              root.dragSourceIndex = i
              break
            }
          }
        }
        root.updateDragOver()
        return
      }
      // The drop. Defer the capture past the bar's own release handling: a
      // synchronous config write here rebuilds the bar mid-gesture, which
      // tears down the source slot's context while its release handler is
      // still on the stack (ReferenceError in Bar.qml, and the release leaks
      // to whatever sits under the cursor). The closure keeps only the shell
      // reference and plain values, so it survives this widget's own
      // destruction in the rebuild that the bar's adjacent-slot move causes.
      var wanted = root.dragOver ? root.dragSourceId : ""
      var from = root.dragSourceRegion
      var at = root.dragSourceIndex
      root.dragOver = false
      root.dragSourceId = ""
      root.dragSourceRegion = ""
      root.dragSourceIndex = -1
      if (!wanted) return
      var shellRef = root.bar ? root.bar.shell : null
      var trayId = root.moduleName || "io.github.tyrichards.tray"
      if (!shellRef || typeof shellRef.mutateShellConfig !== "function") return
      Qt.callLater(function() {
        shellRef.mutateShellConfig(function(config) {
          TrayModel.captureIntoTray(config, trayId, wanted, from, at)
        })
      })
    }

    function onBarDragSceneXChanged() { root.updateDragOver() }
    function onBarDragSceneYChanged() { root.updateDragOver() }
  }

  function restoreWidget(widgetId) {
    var shell = root.bar ? root.bar.shell : null
    if (!shell || typeof shell.mutateShellConfig !== "function") return
    var trayId = root.moduleName || "io.github.tyrichards.tray"
    shell.mutateShellConfig(function(config) {
      TrayModel.restoreFromTray(config, trayId, widgetId)
    })
  }

  function togglePinWidget(widgetId) {
    var next = pinnedWidgetIds.slice()
    var index = next.indexOf(widgetId)
    if (index !== -1) next.splice(index, 1)
    else next.push(widgetId)
    persistState({ pinnedWidgets: next })
  }

  function widgetDisplayName(widgetId) {
    var registry = root.bar ? root.bar.barWidgetRegistry : null
    var meta = registry && typeof registry.metadataFor === "function" ? registry.metadataFor(widgetId) : null
    if (meta) {
      if (meta.barWidget && meta.barWidget.displayName) return String(meta.barWidget.displayName)
      if (meta.name) return String(meta.name)
    }
    return widgetId
  }

  // ---------------------------------------------------------------------------
  // Submenu drill-down state. QsMenuEntry.display() renders a *platform* menu,
  // which Quickshell refuses unless the shell root sets `//@ pragma
  // UseQApplication` - omarchy's shell.qml does not, so every submenu click was
  // a silent no-op and apps whose whole UI is submenus were unusable.
  // QsMenuEntry inherits QsMenuHandle, so a child entry can feed a nested
  // QsMenuOpener and render inside this popup instead of going through the
  // platform. Each level keeps its own live opener: a child entry is owned by
  // its parent opener's model, so collapsing the stack to a single opener
  // would destroy the very entry being displayed.
  // ---------------------------------------------------------------------------
  property var submenuStack: []
  readonly property int submenuDepth: submenuStack.length
  readonly property string currentTitle: submenuDepth > 0 ? submenuStack[submenuDepth - 1].title : ""
  readonly property var currentChildren: submenuDepth > 0
    ? submenuStack[submenuDepth - 1].opener.children
    : trayMenuOpener.children

  // Changing level rebuilds the row delegates synchronously, so the next
  // row lands under a cursor that hasn't moved. Ignore row clicks for a beat
  // after each level change; a deliberate follow-up click is slower.
  property bool menuLevelSettling: false

  Component {
    id: submenuOpenerComponent
    QsMenuOpener {}
  }

  Timer {
    id: menuLevelSettleTimer
    interval: 250
    onTriggered: root.menuLevelSettling = false
  }

  function settleMenuLevel() {
    menuLevelSettling = true
    menuLevelSettleTimer.restart()
  }

  function resetTrayMenu() {
    menuLevelSettling = false
    menuLevelSettleTimer.stop()
    // Flickable keeps its offset across a model swap whenever the new content
    // is still tall enough to hold it, so a menu dismissed while scrolled
    // would otherwise reopen part-way down with its first entries off screen.
    trayMenuFlick.contentY = 0
    // Clear the reactive stack before tearing anything down, then destroy
    // deepest first: an inner opener's menu entry is owned by its parent's
    // children model.
    var openers = submenuStack
    submenuStack = []
    for (var i = openers.length - 1; i >= 0; i--) openers[i].opener.destroy()
  }

  function enterSubmenu(entry, title) {
    var opener = submenuOpenerComponent.createObject(root, { menu: entry })
    if (!opener) return
    var stack = submenuStack.slice()
    stack.push({ opener: opener, title: title })
    submenuStack = stack
    settleMenuLevel()
  }

  function leaveSubmenu() {
    if (submenuStack.length === 0) return
    var stack = submenuStack.slice()
    var top = stack.pop()
    submenuStack = stack
    top.opener.destroy()
    settleMenuLevel()
  }

  function close() {
    managePopupOpen = false
    trayMenuOpen = false
  }

  function openTrayMenu(item, anchorItem, mouse) {
    if (!item || !item.menu) {
      var point = anchorItem.QsWindow.contentItem.mapFromItem(anchorItem, mouse.x, mouse.y)
      item.display(anchorItem.QsWindow.window, point.x, point.y)
      return
    }

    // Reset before switching items: trayMenuOpener.menu binds to
    // activeTrayItem.menu, so assigning a new item invalidates the old root's
    // children immediately.
    resetTrayMenu()
    activeTrayItem = item
    activeTrayAnchor = anchorItem
    trayMenuOpen = true
  }

  function trayIconSource(icon) {
    // Quickshell already resolves the tray icon into a ready-to-use image://
    // URL, including a "?path=" fallback search dir for apps that ship their
    // tray icon outside a standard theme.
    return String(icon || "")
  }

  // Symbolic icons ship a fixed fill the host is meant to recolor; detect by
  // the freedesktop "-symbolic" name suffix so they can be tinted.
  function iconIsSymbolic(icon) {
    var name = String(icon || "").split("?")[0]
    return name.slice(-9) === "-symbolic"
  }

  function trayTooltip(item) {
    return item.tooltipTitle || item.title || item.id || ""
  }

  function classifyItem(item) {
    var iid = String(item.id || "")
    if (hiddenIds.indexOf(iid) !== -1) return "hidden"
    if (pinnedIds.indexOf(iid) !== -1) return "pinned"
    return "drawer"
  }

  function ownedByOmarchy(item) {
    var layout = root.bar && root.bar.layoutConfig ? root.bar.layoutConfig : null
    return TrayModel.ownedByOmarchy(item, layout)
  }

  function bucket(category) {
    var values = SystemTray.items.values
    var result = []
    for (var i = 0; i < values.length; i++) {
      var item = values[i]
      if (item.status === Status.Passive) continue
      if (ownedByOmarchy(item)) continue
      if (category === "all") {
        result.push(item)
        continue
      }
      if (classifyItem(item) === category) result.push(item)
    }
    return result
  }

  // Writes the widget's full inline state. updateEntryInline replaces the
  // whole layout entry, so every persisted key has to ride along on every
  // write or a pin toggle would silently drop the captured widgets.
  function persistState(overrides) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var id = root.moduleName || "io.github.tyrichards.tray"
    var payload = { id: id }
    var current = root.settings || {}
    for (var key in current) {
      if (key !== "id") payload[key] = current[key]
    }
    payload.pinned = root.pinnedIds
    payload.hidden = root.hiddenIds
    for (var name in overrides) payload[name] = overrides[name]
    root.bar.shell.updateEntryInline(id, payload)
  }

  function togglePin(iid) {
    var p = pinnedIds.slice(), h = hiddenIds.slice()
    var idx = p.indexOf(iid)
    if (idx !== -1) p.splice(idx, 1)
    else {
      p.push(iid)
      var hi = h.indexOf(iid)
      if (hi !== -1) h.splice(hi, 1)
    }
    persistState({ pinned: p, hidden: h })
  }

  function toggleHide(iid) {
    var p = pinnedIds.slice(), h = hiddenIds.slice()
    var idx = h.indexOf(iid)
    if (idx !== -1) h.splice(idx, 1)
    else {
      h.push(iid)
      var pi = p.indexOf(iid)
      if (pi !== -1) p.splice(pi, 1)
    }
    persistState({ pinned: p, hidden: h })
  }

  // Stay on screen while a drag is in flight even when otherwise empty, so
  // there is always a drop target to aim at.
  visible: pinnedItems.length > 0 || drawerCount > 0 || hostedWrappers.length > 0 || dragActive
  clip: false
  implicitWidth: root.vertical ? root.barSize : trayContent.implicitWidth
  implicitHeight: root.vertical ? trayContent.implicitHeight : root.barSize

  Loader {
    id: trayContent
    anchors.fill: parent
    sourceComponent: root.vertical ? verticalTray : horizontalTray
  }

  // Drop-target highlight while a dragged widget hovers over the tray.
  Rectangle {
    anchors.fill: parent
    visible: root.dragOver
    color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)
    border.color: Color.accent
    border.width: 1
    radius: Math.min(Style.cornerRadius, height / 2)
    z: 40
  }

  Component {
    id: horizontalTray

    Item {
      id: horizontalTrayRoot

      // Content-driven: unlike the stock tray's fixed icon-count math, the
      // drawer holds arbitrary widgets, so its extent is whatever the row
      // measures. The widget grows only while revealed rather than reserving
      // the expanded width — with whole widgets inside, a permanent reserved
      // gap could hollow out most of the bar.
      readonly property real drawerExtent: drawerRow.implicitWidth
      readonly property real revealExtent: drawerExtent * root.revealProgress
      readonly property bool showDrawerBlock: root.hasDrawerContent || root.dragActive
      readonly property real drawerBlockWidth: showDrawerBlock ? expandIcon.implicitWidth + revealExtent : 0

      implicitWidth: drawerBlockWidth + pinnedRow.implicitWidth
      implicitHeight: root.barSize

      Item {
        id: drawerArea
        x: 0
        width: horizontalTrayRoot.drawerBlockWidth
        height: root.barSize
        visible: horizontalTrayRoot.showDrawerBlock

        HoverHandler {
          onHoveredChanged: root.expanded = hovered
        }

        BarIconButton {
          id: expandIcon
          bar: root.bar
          width: implicitWidth
          height: implicitHeight
          x: 0
          text: "\uf053"
          onPressed: function(button) {
            if (button === Qt.RightButton) root.managePopupOpen = !root.managePopupOpen
          }
        }

        Item {
          id: trayClip
          x: expandIcon.implicitWidth
          anchors.verticalCenter: parent.verticalCenter
          width: horizontalTrayRoot.revealExtent
          height: root.barSize
          clip: true

          Row {
            id: drawerRow
            // Right-anchored inside the clip: the drawer's inner edge stays
            // put against the pinned items while the reveal uncovers content
            // leftward, matching the stock slide.
            x: horizontalTrayRoot.revealExtent - horizontalTrayRoot.drawerExtent
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Repeater {
              model: root.hostedDrawer
              HostedWidget {}
            }

            Repeater {
              model: root.drawerItems
              TrayItem {}
            }
          }
        }
      }

      Row {
        id: pinnedRow
        x: horizontalTrayRoot.drawerBlockWidth
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Repeater {
          model: root.hostedPinned
          HostedWidget {}
        }

        Repeater {
          model: root.pinnedItems
          TrayItem {}
        }
      }
    }
  }

  Component {
    id: verticalTray

    Item {
      id: verticalTrayRoot

      readonly property real drawerExtent: drawerColumn.implicitHeight
      readonly property real revealExtent: drawerExtent * root.revealProgress
      readonly property bool showDrawerBlock: root.hasDrawerContent || root.dragActive
      readonly property real drawerBlockHeight: showDrawerBlock ? expandIcon.implicitHeight + revealExtent : 0

      implicitWidth: root.barSize
      implicitHeight: drawerBlockHeight + pinnedCol.implicitHeight

      Item {
        id: drawerArea
        y: 0
        width: root.barSize
        height: verticalTrayRoot.drawerBlockHeight
        visible: verticalTrayRoot.showDrawerBlock

        HoverHandler {
          onHoveredChanged: root.expanded = hovered
        }

        BarIconButton {
          id: expandIcon
          bar: root.bar
          width: implicitWidth
          height: implicitHeight
          y: 0
          text: "\uf053"
          textRotation: 90
          onPressed: function(button) {
            if (button === Qt.RightButton) root.managePopupOpen = !root.managePopupOpen
          }
        }

        Item {
          id: trayClip
          y: expandIcon.implicitHeight
          anchors.horizontalCenter: parent.horizontalCenter
          width: root.barSize
          height: verticalTrayRoot.revealExtent
          clip: true

          Column {
            id: drawerColumn
            y: verticalTrayRoot.revealExtent - verticalTrayRoot.drawerExtent
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0

            Repeater {
              model: root.hostedDrawer
              HostedWidget {}
            }

            Repeater {
              model: root.drawerItems
              TrayItem {}
            }
          }
        }
      }

      Column {
        id: pinnedCol
        y: verticalTrayRoot.drawerBlockHeight
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 0

        Repeater {
          model: root.hostedPinned
          HostedWidget {}
        }

        Repeater {
          model: root.pinnedItems
          TrayItem {}
        }
      }
    }
  }

  PopupCard {
    id: managePopup
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.managePopupOpen
    contentWidth: managePopup.fittedContentWidth(Style.space(320))
    contentHeight: managePopup.fittedContentHeight(manageColumn.implicitHeight)

    Column {
      id: manageColumn
      anchors.fill: parent
      spacing: Style.space(8)

      Text {
        text: "Tray"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        text: "Drag any bar widget onto the tray to tuck it into the drawer. Pinned items stay visible; hidden tray icons never show."
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        width: parent.width
      }

      Text {
        visible: root.hostedWrappers.length > 0
        text: "Widgets"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Repeater {
        model: root.hostedWrappers
        delegate: Item {
          id: widgetRow
          required property var modelData
          required property int index
          width: manageColumn.width
          implicitHeight: 28

          readonly property string widgetId: TrayModel.wrapperId(modelData)
          readonly property bool isPinned: root.pinnedWidgetIds.indexOf(widgetId) !== -1

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: widgetRestoreBtn.left
            anchors.rightMargin: Style.space(8)
            text: root.widgetDisplayName(widgetRow.widgetId)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Button {
            id: widgetPinBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            iconText: "\uf08d"
            text: widgetRow.isPinned ? "Unpin" : "Pin"
            foreground: root.foreground
            horizontalPadding: 8
            verticalPadding: 3
            iconSize: Style.font.bodySmall
            fontSize: Style.font.bodySmall
            onClicked: root.togglePinWidget(widgetRow.widgetId)
          }

          Button {
            id: widgetRestoreBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: widgetPinBtn.left
            anchors.rightMargin: Style.space(6)
            iconText: "\uf0e2"
            text: "Restore"
            foreground: root.foreground
            horizontalPadding: 8
            verticalPadding: 3
            iconSize: Style.font.bodySmall
            fontSize: Style.font.bodySmall
            onClicked: root.restoreWidget(widgetRow.widgetId)
          }
        }
      }

      Text {
        visible: root.allItems.length > 0
        text: "Tray icons"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Text {
        visible: root.allItems.length === 0 && root.hostedWrappers.length === 0
        text: "Nothing in the tray yet."
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.italic: true
      }

      Repeater {
        model: root.allItems
        delegate: Item {
          id: rowRoot
          required property var modelData
          required property int index
          width: manageColumn.width
          implicitHeight: 28

          readonly property string itemId: String(modelData.id || "")
          readonly property string displayName: {
            var t = String(modelData.title || "").trim()
            if (t) return t
            var tt = String(modelData.tooltipTitle || "").trim()
            if (tt) return tt
            var id = String(modelData.id || "")
            var slash = id.lastIndexOf("/")
            return slash !== -1 ? id.substring(slash + 1) : (id || "Unknown")
          }
          readonly property bool isPinned: root.pinnedIds.indexOf(itemId) !== -1
          readonly property bool isHidden: root.hiddenIds.indexOf(itemId) !== -1

          TrayIcon {
            id: rowIcon
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            width: 16
            height: 16
            icon: rowRoot.modelData.icon
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: rowIcon.right
            anchors.leftMargin: Style.space(10)
            anchors.right: rowHideBtn.left
            anchors.rightMargin: Style.space(8)
            text: rowRoot.displayName
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Button {
            id: rowPinBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            iconText: "\uf08d"
            text: rowRoot.isPinned ? "Unpin" : "Pin"
            foreground: root.foreground
            horizontalPadding: 8
            verticalPadding: 3
            iconSize: Style.font.bodySmall
            fontSize: Style.font.bodySmall
            onClicked: root.togglePin(rowRoot.itemId)
          }

          Button {
            id: rowHideBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: rowPinBtn.left
            anchors.rightMargin: Style.space(6)
            iconText: "\uf06e"
            text: rowRoot.isHidden ? "Show" : "Hide"
            foreground: root.foreground
            horizontalPadding: 8
            verticalPadding: 3
            iconSize: Style.font.bodySmall
            fontSize: Style.font.bodySmall
            onClicked: root.toggleHide(rowRoot.itemId)
          }
        }
      }
    }
  }

  QsMenuOpener {
    id: trayMenuOpener
    menu: root.activeTrayItem ? root.activeTrayItem.menu : null
  }

  PopupCard {
    id: trayMenuPopup
    anchorItem: root.activeTrayAnchor || root
    owner: root
    bar: root.bar
    open: root.trayMenuOpen
    // The card fades out over 140ms (visible stays true for that whole time),
    // so resetting on "open" would swap a live submenu for the root menu
    // mid-fade. Wait for the fade to actually finish. Switching to a different
    // tray item still resets immediately, from openTrayMenu() itself.
    onVisibleChanged: if (!visible) root.resetTrayMenu()
    padding: Style.space(8)
    borderColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45)
    contentWidth: trayMenuPopup.fittedContentWidth(Style.space(232))
    contentHeight: trayMenuPopup.fittedContentHeight(menuHeaderHeight + trayMenuColumn.implicitHeight, Style.space(420))

    // Column skips invisible children but keeps reporting their height, so
    // read the header's extent through its own visibility.
    readonly property int menuHeaderHeight: menuHeader.visible ? menuHeader.implicitHeight : 0

    Column {
      id: trayMenuLayout
      anchors.fill: parent
      spacing: 0

      // Header for a drilled-into submenu: names where we are and walks back
      // out. Pinned above the Flickable so the way back stays reachable in a
      // submenu taller than the card. Only present below the root level.
      Column {
        id: menuHeader
        visible: root.submenuDepth > 0
        width: trayMenuLayout.width
        spacing: 0

        Item {
          id: menuBackRow
          width: menuHeader.width
          implicitHeight: Style.space(30)

          Rectangle {
            anchors.fill: parent
            radius: Math.max(2, Style.cornerRadius)
            color: backMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            width: Style.space(22)
            horizontalAlignment: Text.AlignHCenter
            text: "‹"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.space(28)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            text: root.currentTitle
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          MouseArea {
            id: backMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.menuLevelSettling) return
              // Reset before the model swap so the parent level shows from
              // the top (same ordering as the row delegate below).
              trayMenuFlick.contentY = 0
              root.leaveSubmenu()
            }
          }
        }

        Item {
          width: menuHeader.width
          implicitHeight: Style.space(11)

          Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            height: 1
            color: Color.popups.border
            opacity: 0.45
          }
        }
      }

      Flickable {
        id: trayMenuFlick
        width: trayMenuLayout.width
        height: trayMenuLayout.height - trayMenuPopup.menuHeaderHeight
        contentWidth: width
        contentHeight: trayMenuColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: trayMenuColumn
          width: trayMenuFlick.width
          spacing: 0

          Repeater {
            model: root.currentChildren

            delegate: Item {
              id: menuRow
              required property var modelData
              required property int index

              readonly property string rowText: String(modelData.text || "")
              readonly property string activeTitle: root.activeTrayItem ? String(root.activeTrayItem.title || root.activeTrayItem.id || "") : ""
              // Both only ever describe the root menu; inside a submenu the
              // first rows are real entries and must not be swallowed.
              readonly property bool atRoot: root.submenuDepth === 0
              readonly property bool rootTitleEntry: atRoot && index === 0 && modelData.hasChildren && rowText.toLowerCase() === activeTitle.toLowerCase()
              readonly property bool leadingSeparator: atRoot && modelData.isSeparator && index <= 1
              readonly property bool hiddenRow: rootTitleEntry || leadingSeparator

              visible: !hiddenRow
              width: trayMenuColumn.width
              implicitHeight: hiddenRow ? 0 : (modelData.isSeparator ? Style.space(11) : Style.space(30))
              opacity: modelData.enabled ? 1.0 : 0.45

              Rectangle {
                visible: menuRow.modelData.isSeparator
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                height: 1
                color: Color.popups.border
                opacity: 0.45
              }

              Rectangle {
                visible: !menuRow.modelData.isSeparator
                anchors.fill: parent
                radius: Math.max(2, Style.cornerRadius)
                color: rowMouse.containsMouse && menuRow.modelData.enabled ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
              }

              Text {
                visible: !menuRow.modelData.isSeparator && menuRow.modelData.buttonType !== QsMenuButtonType.None
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                width: Style.space(22)
                horizontalAlignment: Text.AlignHCenter
                text: menuRow.modelData.checkState === Qt.Checked ? "\uf00c" : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Image {
                id: menuIcon
                visible: !menuRow.modelData.isSeparator && String(menuRow.modelData.icon || "") !== ""
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(24)
                width: Style.space(16)
                height: Style.space(16)
                fillMode: Image.PreserveAspectFit
                // Decode at physical pixels: IconImage uses the logical size,
                // which leaves PNG icons upscaled and blurry on HiDPI.
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: menuRow.modelData.icon
              }

              Text {
                visible: !menuRow.modelData.isSeparator
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: menuIcon.visible ? Style.space(46) : Style.space(28)
                anchors.right: submenuGlyph.left
                anchors.rightMargin: Style.space(8)
                text: menuRow.rowText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                id: submenuGlyph
                visible: !menuRow.modelData.isSeparator && menuRow.modelData.hasChildren
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                text: "›"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: !menuRow.modelData.isSeparator && menuRow.modelData.enabled
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                  if (root.menuLevelSettling) return
                  if (menuRow.modelData.hasChildren) {
                    // Reset scroll BEFORE swapping the model: the swap
                    // destroys this delegate synchronously and ids stop
                    // resolving after.
                    trayMenuFlick.contentY = 0
                    root.enterSubmenu(menuRow.modelData, menuRow.rowText)
                  } else {
                    menuRow.modelData.triggered()
                    root.close()
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // Renders a tray icon, recoloring symbolic icons to the bar foreground so
  // they stay visible on any theme.
  component TrayIcon: Item {
    id: trayIconRoot
    required property var icon
    readonly property bool symbolic: root.iconIsSymbolic(icon)

    Image {
      id: trayIconImage
      anchors.fill: parent
      fillMode: Image.PreserveAspectFit
      // Decode at physical pixels: IconImage uses the logical size, which
      // leaves PNG icons upscaled and blurry on HiDPI displays.
      sourceSize.width: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      sourceSize.height: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      source: root.trayIconSource(trayIconRoot.icon)
      // Kept as a hidden layer so the effect can sample it as a texture.
      visible: !trayIconRoot.symbolic
      layer.enabled: trayIconRoot.symbolic
    }

    MultiEffect {
      anchors.fill: trayIconImage
      source: trayIconImage
      visible: trayIconRoot.symbolic
      colorization: 1.0
      colorizationColor: root.foreground
    }
  }

  component TrayItem: Item {
    id: trayItemRoot

    required property var modelData

    visible: modelData.status !== Status.Passive
    implicitWidth: visible ? root.trayItemExtent : 0
    implicitHeight: visible ? root.trayItemExtent : 0

    function displayMenu(mouse) {
      root.openTrayMenu(trayItemRoot.modelData, trayItemRoot, mouse)
    }

    TrayIcon {
      anchors.centerIn: parent
      width: Style.space(12)
      height: Style.space(12)
      icon: trayItemRoot.modelData.icon
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.bar) root.bar.showTooltip(trayItemRoot, root.trayTooltip(modelData))
      onExited: if (root.bar) root.bar.hideTooltip(trayItemRoot)
      onPressed: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          trayItemRoot.displayMenu(mouse)
          mouse.accepted = true
        }
      }
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          mouse.accepted = true
        } else if (mouse.button === Qt.MiddleButton) {
          trayItemRoot.modelData.secondaryActivate()
        } else if (trayItemRoot.modelData.onlyMenu) {
          trayItemRoot.displayMenu(mouse)
        } else {
          trayItemRoot.modelData.activate()
        }
      }
      onWheel: function(wheel) {
        trayItemRoot.modelData.scroll(wheel.angleDelta.y, false)
      }
    }

    readonly property bool tooltipHovered: visible && opacity > 0 && mouseArea.containsMouse
  }

  // A captured bar widget living inside the tray. Instantiates the same
  // registry component the bar's own module slots use and injects the same
  // three properties (bar, moduleName, settings), so the widget cannot tell
  // it isn't sitting directly in a bar section — clicks route through the
  // bar's registered click targets, tooltips and panels anchor normally.
  component HostedWidget: Item {
    id: hostedRoot

    required property var modelData

    readonly property var entry: modelData && modelData.entry ? modelData.entry : ({})
    readonly property string widgetId: TrayModel.entryId(entry)
    readonly property var widgetSettings: TrayModel.entrySettings(entry)
    readonly property string customType: root.bar && typeof root.bar.customModuleType === "function"
      ? String(root.bar.customModuleType(entry) || "") : ""
    readonly property var registryComponent: {
      if (customType) return null
      var registry = root.bar ? root.bar.barWidgetRegistry : null
      if (!registry) return null
      var revision = registry.revision
      var record = registry.widgets[widgetId]
      return record ? record.component : null
    }
    readonly property var activeItem: {
      if (registryComponent) return registryLoader.item
      if (customType === "qml") return qmlLoader.item
      if (customType === "command") return commandLoader.item
      return null
    }

    implicitWidth: activeItem && activeItem.visible ? (root.vertical ? root.barSize : activeItem.implicitWidth) : 0
    implicitHeight: activeItem && activeItem.visible ? (root.vertical ? activeItem.implicitHeight : root.barSize) : 0
    width: implicitWidth
    height: implicitHeight

    onActiveItemChanged: Qt.callLater(injectProps)
    onWidgetSettingsChanged: injectProps()

    function injectProps() {
      var target = activeItem
      if (!target) return
      if ("bar" in target) target.bar = root.bar
      if ("moduleName" in target) target.moduleName = widgetId
      if ("settings" in target) target.settings = widgetSettings
    }

    Loader {
      id: registryLoader
      active: hostedRoot.registryComponent !== null
      sourceComponent: hostedRoot.registryComponent
      anchors.fill: parent
      onLoaded: {
        hostedRoot.injectProps()
        Qt.callLater(hostedRoot.injectProps)
      }
    }

    Loader {
      id: qmlLoader
      active: hostedRoot.customType === "qml"
      source: active && root.bar && typeof root.bar.customModuleSource === "function"
        ? root.bar.customModuleSource(hostedRoot.entry) : ""
      anchors.fill: parent
      onLoaded: {
        hostedRoot.injectProps()
        Qt.callLater(hostedRoot.injectProps)
      }
    }

    Loader {
      id: commandLoader
      active: hostedRoot.customType === "command"
      sourceComponent: hostedCommandComponent
      anchors.fill: parent
      onLoaded: item.entry = hostedRoot.entry
    }
  }

  // Minimal clone of the bar's private exec-based custom module, so command
  // widgets can live inside the tray too.
  Component {
    id: hostedCommandComponent

    WidgetButton {
      id: commandRoot

      property var entry: ({})
      readonly property var moduleSettings: TrayModel.entrySettings(entry)
      property string outputText: ""
      property string outputTooltip: ""
      property bool outputActive: false

      function setting(name, fallback) {
        var value = moduleSettings ? moduleSettings[name] : undefined
        return value === undefined || value === null ? fallback : value
      }

      function update(raw) {
        var data = Util.parseModuleJson(raw)
        var klass = data.class || data.alt || ""
        outputText = data.text || String(raw || "").trim()
        outputTooltip = data.tooltip || String(setting("tooltip", ""))
        outputActive = klass === "active" || (Array.isArray(klass) && klass.indexOf("active") !== -1)
      }

      bar: root.bar
      text: outputText || String(setting("text", ""))
      tooltipText: outputTooltip || String(setting("tooltip", ""))
      active: outputActive
      keepSpace: setting("keepSpace", false) === true
      horizontalMargin: Number(setting("horizontalMargin", 7.5))
      verticalPadding: Number(setting("verticalPadding", 6))
      fontSize: Number(setting("fontSize", 12))

      onPressed: function(button) {
        var command = ""
        if (button === Qt.RightButton)
          command = String(setting("onRightClick", ""))
        else if (button === Qt.MiddleButton)
          command = String(setting("onMiddleClick", ""))
        else
          command = String(setting("onClick", ""))

        if (command && root.bar) root.bar.run(command)
      }

      Process {
        id: commandProc
        command: ["bash", "-lc", String(commandRoot.setting("exec", ""))]
        stdout: StdioCollector {
          waitForEnd: true
          onStreamFinished: commandRoot.update(text)
        }
      }

      Timer {
        interval: Math.max(1, Number(commandRoot.setting("interval", 5))) * 1000
        running: String(commandRoot.setting("exec", "")) !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!commandProc.running) commandProc.running = true
      }
    }
  }
}
