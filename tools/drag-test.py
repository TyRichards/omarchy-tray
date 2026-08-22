#!/usr/bin/env python3
"""End-to-end drag test for the Tray plugin, via injected input.

Usage: tools/drag-test.py [source-widget-id]   (default: omarchy.tailscale)

Phases:
  1. drag the source widget from the bar onto the tray -> captured in config
  2. hover the chevron -> the drawer must physically expand (render check)
  3. drag the hosted widget back out of the open drawer onto the bar
     -> entry returns to the bar layout, tray's widgets list is empty

Requires tools/vptr/vptr (run tools/vptr/build.sh once) and a running
omarchy-shell. Uses the real pointer, so keep hands off the mouse while it
runs. Ends with the widget back in the bar, roughly where it was dropped.
"""
import json
import pathlib
import subprocess
import sys
import time

TRAY_ID = "io.github.tyrichards.tray"
SOURCE = sys.argv[1] if len(sys.argv) > 1 else "omarchy.tailscale"
VPTR = pathlib.Path(__file__).parent / "vptr" / "vptr"
CHEVRON = 32  # BarIconButton slot width; first hosted widget sits right after it


def geometry():
    out = subprocess.check_output(["omarchy-shell", "shell", "debugBarGeometry"])
    return {s["id"]: s for s in json.loads(out) if s.get("visible")}


def cursorpos():
    x, y = subprocess.check_output(["hyprctl", "cursorpos"]).decode().strip().split(",")
    return float(x), float(y)


def screen_extent():
    mon = next(m for m in json.loads(subprocess.check_output(["hyprctl", "monitors", "-j"])) if m["focused"])
    return round(mon["width"] / mon["scale"]), round(mon["height"] / mon["scale"])


def tray_state():
    config = json.load(open(pathlib.Path.home() / ".config/omarchy/shell.json"))
    hosted, in_layout = None, False
    for section in config["bar"]["layout"].values():
        for entry in section:
            if not isinstance(entry, dict):
                continue
            if entry.get("id") == TRAY_ID:
                for w in entry.get("widgets", []):
                    if w.get("entry", {}).get("id") == SOURCE:
                        hosted = w
            elif entry.get("id") == SOURCE:
                in_layout = True
    return hosted, in_layout


def main():
    if not VPTR.exists():
        sys.exit(f"{VPTR} missing — run tools/vptr/build.sh first")
    geo = geometry()
    if TRAY_ID not in geo or SOURCE not in geo:
        sys.exit(f"need both {TRAY_ID} and {SOURCE} visible in the bar, have: {sorted(geo)}")

    tray, src = geo[TRAY_ID], geo[SOURCE]
    bar_y = src["y"] + src["height"] / 2
    ext_w, ext_h = screen_extent()

    vp = subprocess.Popen([str(VPTR)], stdin=subprocess.PIPE, text=True, bufsize=1)
    cmd = lambda s: (vp.stdin.write(s + "\n"), vp.stdin.flush())

    def glide_to(end):
        for _ in range(80):
            cx, cy = cursorpos()
            dx, dy = end[0] - cx, end[1] - cy
            if abs(dx) < 1.5 and abs(dy) < 1.5:
                break
            cmd(f"move {max(-4, min(4, dx))} {max(-4, min(4, dy))}")
            time.sleep(0.05)

    def finish(message):
        cmd(f"abs 705 485 {ext_w} {ext_h}")
        time.sleep(0.2)
        vp.stdin.close()
        vp.wait(timeout=5)
        sys.exit(message)

    # Phase 1: drag the widget from the bar into the tray. Hovering the bar
    # can reshuffle widgets under the cursor (the center section reveals the
    # indicators widget on hover, shifting its neighbours), so re-aim until
    # the source's position is stable before pressing — otherwise the drag
    # grabs whatever slid underneath.
    for _ in range(6):
        src = geometry()[SOURCE]
        target = (src["x"] + src["width"] / 2, bar_y)
        cmd(f"abs {target[0]:.0f} {target[1]:.0f} {ext_w} {ext_h}")
        time.sleep(0.8)
        settled = geometry()[SOURCE]
        if abs(settled["x"] - src["x"]) < 2 and abs(settled["width"] - src["width"]) < 2:
            break
    cmd("press")
    time.sleep(0.2)
    glide_to((tray["x"] + tray["width"] / 2, bar_y))
    time.sleep(0.4)
    cmd("release")
    time.sleep(1)

    hosted, in_layout = tray_state()
    if not hosted:
        finish(f"FAIL(capture): {SOURCE} not found in the tray's widgets list")
    print("PASS: captured", json.dumps(hosted))

    # Phase 2: hover the chevron; the drawer must physically expand, proving
    # the captured widget instantiates with nonzero size (the "black hole"
    # regression, where capture worked but nothing rendered). Park the cursor
    # away first: after the drop it still sits on the tray, holding the
    # drawer open, and a pre-expanded tray would false-fail the check.
    cmd(f"abs 705 485 {ext_w} {ext_h}")
    time.sleep(1.5)
    tray = geometry()[TRAY_ID]
    cmd(f"abs {tray['x'] + tray['width'] - 8:.0f} {bar_y:.0f} {ext_w} {ext_h}")
    time.sleep(0.15)
    cmd("move -2 1")
    time.sleep(1.3)
    expanded = geometry()[TRAY_ID]
    if expanded["width"] <= tray["width"]:
        finish(f"FAIL(render): drawer did not expand on hover ({tray['width']} -> {expanded['width']})")
    print(f"PASS: drawer expands and renders ({tray['width']} -> {expanded['width']})")

    # Phase 3: with the drawer open, drag the hosted widget (first item after
    # the chevron) back out onto the bar, dropping in the gap left of the tray.
    cmd(f"abs {expanded['x'] + CHEVRON + 12:.0f} {bar_y:.0f} {ext_w} {ext_h}")
    time.sleep(0.3)
    cmd("press")
    time.sleep(0.2)
    glide_to((expanded["x"] - 140, bar_y))
    time.sleep(0.4)
    cmd("release")
    time.sleep(1.5)

    hosted, in_layout = tray_state()
    if hosted or not in_layout:
        finish(f"FAIL(drag-out): hosted={hosted is not None} in_layout={in_layout}")
    print("PASS: dragged back out to the bar")

    cmd(f"abs 705 485 {ext_w} {ext_h}")
    time.sleep(0.2)
    vp.stdin.close()
    vp.wait(timeout=5)


if __name__ == "__main__":
    main()
