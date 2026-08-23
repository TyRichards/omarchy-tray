```text
▄
█▀▀ █▀▀ ▄▀█ █ █
▀▀  ▀   ▀▀▀ ▀▀█
by Ty Richards
```

A better system tray for the [Omarchy](https://omarchy.org/) bar.

Everything the stock `omarchy.tray` does — status notifier icons, pin/hide,
the slide-out chevron drawer, in-popup app menus with submenu drill-down —
plus one big upgrade: **drag any bar widget onto the tray and it moves inside
the drawer.**

The clock, the workspaces, the menu, weather, network, audio, power, custom
modules, third-party plugin widgets — anything that lives in the bar layout
can be tucked into the tray. Taken to the limit, your bar can be nothing but
this tray, with everything else sliding out on hover.

![The tray's drawer and manage popup](preview.png)

![Drawer, capture, and reorder in action](demo.gif)

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
  as reordering the bar). The tray highlights while you are over it and the
  insertion marker shows where the widget will land among the drawer's
  content — release and it slots in exactly there.
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
- **Right-click the chevron** for the manage popup (Escape or click-away
  closes it): a **SHOW SYSTEM ICONS** master toggle (on by default; the icon rows gray out while icons are
  hidden), and one hoverable row per icon — click it to toggle that icon's
  visibility; the eye glyph at the row's edge shows the current state.
  Widgets have no popup controls — dragging is the whole interface.
- While another widget's panel is open, hovering the chevron does not open
  the drawer (the panel's focus grab swallows hover anyway) — click the
  chevron instead: the open panel closes and the drawer opens.
- Captured widgets keep their inline settings, clicks, tooltips, wheel
  actions, and panels. Tray state (what's captured, the drawer order, hidden
  icons) is stored on the tray's own `shell.json` entry, so it survives
  restarts and is shared across monitors.
- On a vertical bar (or with a very wide drawer on a horizontal one) the open
  drawer can overrun the bar's center section; while the drawer is out the
  center widgets are scrimmed and inert so the two never fight.

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
