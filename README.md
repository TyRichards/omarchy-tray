# Tray

A better system tray for the [Omarchy](https://omarchy.org/) bar.

Everything the stock `omarchy.tray` does — status notifier icons, pin/hide,
the slide-out chevron drawer, in-popup app menus with submenu drill-down —
plus one big upgrade: **drag any bar widget onto the tray and it moves inside
the drawer.**

The clock, the workspaces, the menu, weather, network, audio, power, custom
modules, third-party plugin widgets — anything that lives in the bar layout
can be tucked into the tray. Taken to the limit, your bar can be nothing but
this tray, with everything else sliding out on hover.

## Install

```bash
omarchy plugin add https://github.com/TyRichards/omarchy-tray.git --enable --yes
```

Then replace the stock tray with this one (recommended — it is a strict
superset):

```bash
./install.sh          # from the plugin directory, or do it by hand:
```

By hand: in `~/.config/omarchy/shell.json`, change the bar layout entry
`{ "id": "omarchy.tray" }` to `{ "id": "io.github.tyrichards.tray" }`.
The shell hot-reloads on save.

For the smoothest reveal animation, keep the tray at the **inner edge** of its
section (first entry of `right`, or last of `left`): the drawer then expands
into the bar's empty middle without pushing its neighbours around.

## Use

- **Hover the chevron** to slide the drawer open; tray icons and captured
  widgets live inside it.
- **Drag any bar widget onto the tray** (drag starts after a short move, same
  as reordering the bar). The tray highlights while you are over it; release
  to capture the widget into the drawer.
- **Drag a widget back out**: open the drawer, grab the widget, and drag it
  onto the bar — it lands wherever you drop it, with the bar's usual ghost
  and insertion marker.
- **Reorder inside the drawer**: drag anything — plugin widget or system
  tray icon — and release it over the tray; the insertion marker shows where
  it lands. Widgets and icons share one order, so the two kinds interleave
  freely, and the arrangement persists across restarts.
- **Icons stay inside**: a system tray icon can only move within the tray —
  releasing one outside is a no-op, since a status-notifier item has no life
  in the bar layout. Widgets still drag out normally.
- **Drag the chevron to move the whole tray.** The chevron is the tray's only
  whole-widget drag handle; grabbing anything else in the tray never drags
  the tray itself.
- **Right-click the chevron** for the manage popup: a **Show System Tray
  Icons** master toggle, and a **Hide** switch per icon. Widgets have no
  popup controls — dragging is the whole interface.
- Captured widgets keep their inline settings, clicks, tooltips, wheel
  actions, and panels. Widget state (what's captured, what's pinned) is stored
  on the tray's own `shell.json` entry, so it survives restarts and is shared
  across monitors.

## Notes and limitations

- Panel hotkeys (`omarchy-shell` summon/toggle for e.g. the weather panel)
  only find widgets sitting directly in the bar layout; a widget captured into
  the tray still opens its panel by click, but not by hotkey. Restore it to
  the bar if you need the hotkey.
- Exec-based custom modules (`"exec": ...` entries) are supported via a
  built-in clone of the bar's command module; `source:`-based custom QML
  modules load from their original path.
- The drawer sizes itself to its content, so unlike the stock tray it does
  not reserve the expanded width while collapsed.

## License

MIT
