#!/usr/bin/env python3
"""End-to-end drag test: drags a bar widget onto the Tray via injected input.

Usage: tools/drag-test.py [source-widget-id]   (default: omarchy.tailscale)

Requires tools/vptr/vptr (run tools/vptr/build.sh once) and a running
omarchy-shell. Uses the real pointer, so keep hands off the mouse while it
runs. Verifies the widget landed in the tray's `widgets` list and prints the
resulting entry. Restore the widget afterwards from the tray's right-click
manage popup.
"""
import json
import pathlib
import subprocess
import sys
import time

TRAY_ID = "io.github.tyrichards.tray"
SOURCE = sys.argv[1] if len(sys.argv) > 1 else "omarchy.tailscale"
VPTR = pathlib.Path(__file__).parent / "vptr" / "vptr"


def geometry():
    out = subprocess.check_output(["omarchy-shell", "shell", "debugBarGeometry"])
    return {s["id"]: s for s in json.loads(out) if s.get("visible")}


def cursorpos():
    x, y = subprocess.check_output(["hyprctl", "cursorpos"]).decode().strip().split(",")
    return float(x), float(y)


def screen_extent():
    mon = next(m for m in json.loads(subprocess.check_output(["hyprctl", "monitors", "-j"])) if m["focused"])
    return round(mon["width"] / mon["scale"]), round(mon["height"] / mon["scale"])


def main():
    if not VPTR.exists():
        sys.exit(f"{VPTR} missing — run tools/vptr/build.sh first")
    geo = geometry()
    if TRAY_ID not in geo or SOURCE not in geo:
        sys.exit(f"need both {TRAY_ID} and {SOURCE} visible in the bar, have: {sorted(geo)}")

    tray, src = geo[TRAY_ID], geo[SOURCE]
    bar_y = src["y"] + src["height"] / 2
    start = (src["x"] + src["width"] / 2, bar_y)
    end = (tray["x"] + tray["width"] / 2, bar_y)
    ext_w, ext_h = screen_extent()

    vp = subprocess.Popen([str(VPTR)], stdin=subprocess.PIPE, text=True, bufsize=1)
    cmd = lambda s: (vp.stdin.write(s + "\n"), vp.stdin.flush())

    cmd(f"abs {start[0]:.0f} {start[1]:.0f} {ext_w} {ext_h}")
    time.sleep(0.3)
    cmd("press")
    time.sleep(0.2)
    for _ in range(60):
        cx, cy = cursorpos()
        dx, dy = end[0] - cx, end[1] - cy
        if abs(dx) < 1.5 and abs(dy) < 1.5:
            break
        cmd(f"move {max(-4, min(4, dx))} {max(-4, min(4, dy))}")
        time.sleep(0.05)
    time.sleep(0.4)
    cmd("release")
    time.sleep(0.5)
    vp.stdin.close()
    vp.wait(timeout=5)

    time.sleep(1)
    config = json.load(open(pathlib.Path.home() / ".config/omarchy/shell.json"))
    for section in config["bar"]["layout"].values():
        for entry in section:
            if isinstance(entry, dict) and entry.get("id") == TRAY_ID:
                hosted = [w for w in entry.get("widgets", []) if w.get("entry", {}).get("id") == SOURCE]
                if hosted:
                    print("PASS: captured", json.dumps(hosted[0]))
                    return
    sys.exit(f"FAIL: {SOURCE} not found in the tray's widgets list")


if __name__ == "__main__":
    main()
