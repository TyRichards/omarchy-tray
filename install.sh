#!/usr/bin/env bash
# Replace the stock omarchy.tray bar entry with io.github.tyrichards.tray.
# Safe to re-run; the shell hot-reloads shell.json on save.
set -euo pipefail

CONFIG="$HOME/.config/omarchy/shell.json"
ID="io.github.tyrichards.tray"

if [[ ! -f "$CONFIG" ]]; then
  echo "No $CONFIG found — add the widget with:"
  echo "  omarchy bar put $ID --section right --index 0"
  exit 1
fi

if ! command -v jq >/dev/null; then
  echo "jq is required. Install it with: omarchy pkg add jq" >&2
  exit 1
fi

if jq -e --arg id "$ID" '[.bar.layout[][]? | select(.id == $id or . == $id)] | length > 0' "$CONFIG" >/dev/null; then
  echo "$ID is already in the bar layout."
  exit 0
fi

tmp=$(mktemp)
if jq -e '[.bar.layout[][]? | select(.id == "omarchy.tray" or . == "omarchy.tray")] | length > 0' "$CONFIG" >/dev/null; then
  # Swap the stock tray in place, keeping its position in the layout.
  jq --arg id "$ID" '
    .bar.layout |= with_entries(
      .value |= map(
        if (.id? == "omarchy.tray") or (. == "omarchy.tray")
        then { id: $id }
        else . end
      )
    )
  ' "$CONFIG" > "$tmp"
  echo "Replaced omarchy.tray with $ID."
else
  # No stock tray present: put the new tray at the inner edge of the right section.
  jq --arg id "$ID" '.bar.layout.right |= ([{ id: $id }] + (. // []))' "$CONFIG" > "$tmp"
  echo "Added $ID to the right section."
fi
mv "$tmp" "$CONFIG"
