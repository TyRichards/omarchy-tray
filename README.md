```text
██
██████  ██████    ████  ██  ██
██      ██      ██  ██  ██  ██
████    ██      ██████  ██████
                            ██
by Ty Richards
```

A better system tray for the [Omarchy](https://omarchy.org/) bar.

![Drawer, capture, and reorder in action](demo.gif)

Everything the stock `omarchy.tray` does — status notifier icons, pin/hide,
the slide-out chevron drawer, in-popup app menus with submenu drill-down —
plus one big upgrade: **drag any bar widget onto the tray and it moves inside
the drawer.**

The clock, the workspaces, the menu, weather, network, audio, power, custom
modules, third-party plugin widgets — anything that lives in the bar layout
can be tucked into the tray. Taken to the limit, your bar can be nothing but
this tray, with everything else sliding out on hover.

![The tray's drawer and manage popup](preview.png)

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

## Customization

The tray stores its preferences on its own bar entry in
`~/.config/omarchy/shell.json`:

| Setting | Default | Purpose |
| --- | --- | --- |
| `animationDuration` | `600` | Drawer animation duration in milliseconds; set to `0` to disable the animation |
| `showTrayIcons` | `true` | Whether system tray icons are shown |
| `hidden` | `[]` | System tray icon IDs hidden from the drawer |
| `widgets` | `[]` | Bar widgets captured inside the drawer |
| `order` | `[]` | Shared order of captured widgets and system tray icons |

`showTrayIcons` and `hidden` are managed from the chevron's right-click menu;
`widgets` and `order` are managed by dragging items. Normally only
`animationDuration` needs to be edited by hand:

```json
{
  "id": "io.github.tyrichards.tray",
  "animationDuration": 250
}
```

The tray itself can be repositioned by dragging its chevron. For the smoothest
reveal, keep it at the **inner edge** of its section (first entry of `right`,
or last of `left`): the drawer then expands into the bar's empty middle without
pushing its neighbours around.

## Uninstall

Drag any widgets you want to keep out of the tray first (or they will be
restored to the bar layout when you remove their entries by hand), then:

```bash
omarchy plugin remove io.github.tyrichards.tray
```

If you replaced the stock tray, put it back with
`omarchy bar put omarchy.tray --section right --index 0`.

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

## Vertical bars

Everything works the same on a left- or right-edge bar — the drawer slides
out along the bar, and the same drags capture, reorder, and eject widgets.
Because a vertical drawer expands straight through the bar's center section,
the center widgets dim and go inert while the drawer is out (with the bar
background when the bar is opaque, with a translucent tint when it is
transparent), so the two never fight for pixels or clicks.

![Vertical bar: drawer, dimmed center, and manage popup](demo-vertical.gif)

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
