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
plus one big upgrade: **any bar widget can live inside the drawer.**

> **On Omarchy 4, drag is unavailable.** The shell hands a third-party widget
> a `PluginBarApi` facade that carries neither the bar's drag surface nor a
> writable layout, so nothing can be dragged in, reordered across the bar
> boundary, or ejected. The drawer renders and runs the widgets you list in
> `shell.json`; put them there by hand. See
> [issue #9](https://github.com/TyRichards/omarchy-tray/issues/9).

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

For the smoothest reveal animation, keep the tray at the **inner edge** of its
section (first entry of `right`, or last of `left`): the drawer then expands
into the bar's empty middle without pushing its neighbours around.

## Uninstall

Drag any widgets you want to keep out of the tray first (or they will be
restored to the bar layout when you remove their entries by hand), then:

```bash
omarchy plugin remove io.github.tyrichards.tray
```

If you replaced the stock tray, put it back with
`omarchy bar put omarchy.tray --section right --index 0`.

## Use

- **Hover the chevron** to slide the drawer open; tray icons and hosted
  widgets live inside it.
- **Right-click the chevron** for the manage popup (Escape or click-away
  closes it): a **SHOW SYSTEM ICONS** master toggle (on by default; the icon rows gray out while icons are
  hidden), and one hoverable row per icon — click it to toggle that icon's
  visibility; the eye glyph at the row's edge shows the current state.
  Hosted widgets have no popup controls. Add and remove them in `shell.json`,
  as shown below, or by drag where the shell allows it.
- While another widget's panel is open, hovering the chevron does not open
  the drawer (the panel's focus grab swallows hover anyway) — click the
  chevron instead: the open panel closes and the drawer opens.
- Hosted widgets keep their inline settings, clicks, tooltips, wheel
  actions, and panels. Tray state (what the drawer holds, its order, hidden
  icons) is stored on the tray's own `shell.json` entry, so it survives
  restarts and is shared across monitors.

### Filling the drawer by hand

On Omarchy 4 this is the only way, since the shell withholds the drag surface.
Move a widget's layout entry from its bar section into the tray's `widgets`
list, and make sure its plugin id is in the top-level `plugins` array so the
shell keeps loading it. Many ids are there already:

```json
{
  "id": "io.github.tyrichards.tray",
  "widgets": [
    { "entry": { "id": "omarchy.keyboard-layout" }, "listed": true }
  ],
  "order": ["omarchy.keyboard-layout"]
}
```

`entry` is the widget's own layout entry, settings and all, so copy it
verbatim. `order` interleaves hosted widgets and tray icons by id. The shell
reloads `shell.json` on save.

### With drag, where the shell allows it

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

## Vertical bars

Everything works the same on a left- or right-edge bar — the drawer slides
out along the bar.
Because a vertical drawer expands straight through the bar's center section,
the center widgets dim and go inert while the drawer is out (with the bar
background when the bar is opaque, with a translucent tint when it is
transparent), so the two never fight for pixels or clicks.

![Vertical bar: drawer, dimmed center, and manage popup](demo-vertical.gif)

## Notes and limitations

- The tray declares a `service` entry point. The shell gives a third-party bar
  widget no widget registry, and the service is the only place it still hands
  over the widget catalogue the drawer needs. Restart the shell once with
  `omarchy-restart-shell` after upgrading: `omarchy plugin update` only
  rescans, and the QML loader can hold a cached listing for a directory it has
  already read.
- Drag is gone on a shell that sandboxes plugins, as described at the top. The
  drawer itself, the manage popup, hide and show, and the hosted widgets all
  work; only moving widgets by pointer does not.
- Two kinds of hosted widget stay inert. One that reads its own service
  through `bar.shell.serviceFor` gets nothing, because only the built-in bar
  can mint that. One that reads `bar.shell.pluginRegistry` gets nothing either.
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
