#!/usr/bin/env bash
# Draw every layer of config/toucan.keymap as an SVG and a PDF
# (one layer per landscape page).
#
# Usage: scripts/draw-keymap.sh [--svg-only]
#   --svg-only  skip the PDF, so Chrome isn't needed (used by the GitHub build)
#
# Needs: uv (runs keymap-drawer from PyPI) and, for the PDF, Google Chrome.
# Output: keymap-drawer/toucan.yaml, toucan.svg (all layers), toucan.pdf
set -euo pipefail

svg_only=false
[[ "${1:-}" == "--svg-only" ]] && svg_only=true

repo="$(cd "$(dirname "$0")/.." && pwd)"
keymap="$repo/config/toucan.keymap"
layout="$repo/config/toucan.json"
out="$repo/keymap-drawer"

command -v uvx >/dev/null || { echo "error: uv not found (brew install uv)" >&2; exit 1; }

if ! $svg_only; then
    # Chrome: $CHROME if set, else the macOS app, else google-chrome/chromium on PATH.
    chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
    [[ -x "$chrome" ]] || chrome="$(command -v google-chrome || command -v chromium || true)"
    [[ -x "$chrome" ]] || { echo "error: Chrome not found (set CHROME=... or use --svg-only)" >&2; exit 1; }
fi

mkdir -p "$out"

# keymap-drawer 0.23+ needs Python 3.12+. Without these flags uv may fall back
# to an old release whose loose tree-sitter pins no longer work.
# Custom key labels live in keymap-drawer/config.yaml.
kd=(uvx --python 3.13 --from "keymap-drawer>=0.23" keymap -c "$out/config.yaml")

# Keymap -> YAML. -c 12 makes the YAML easier to read (12 keys per row).
"${kd[@]}" parse -c 12 -z "$keymap" > "$out/toucan.yaml"

# All layers in one SVG, handy for viewing in a browser.
"${kd[@]}" draw -j "$layout" "$out/toucan.yaml" > "$out/toucan.svg"
echo "Wrote $out/toucan.svg"

$svg_only && exit 0

# Layer names are the indented keys under "layers:" in the YAML.
layers=$(awk '/^layers:/{f=1; next} /^[^ ]/{f=0} f && /^  [^ -][^:]*:/{sub(/^  /,""); sub(/:.*/,""); print}' "$out/toucan.yaml")

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# One SVG per layer, each on its own page of an HTML file.
html="$tmp/keymap.html"
cat > "$html" <<'EOF'
<!doctype html>
<meta charset="utf-8">
<style>
  @page { size: letter landscape; margin: 0.5in; }
  body { margin: 0; }
  .page { height: 7.4in; display: flex; align-items: center; justify-content: center; break-after: page; }
  .page:last-child { break-after: auto; }
  img { max-width: 100%; max-height: 100%; }
</style>
EOF
for layer in $layers; do
    "${kd[@]}" draw "$out/toucan.yaml" -j "$layout" -s "$layer" > "$tmp/$layer.svg"
    echo "<div class=\"page\"><img src=\"$layer.svg\"></div>" >> "$html"
done

# HTML -> PDF with headless Chrome (a throwaway profile avoids clashing with
# a Chrome window you already have open).
"$chrome" --headless --disable-gpu --no-pdf-header-footer \
    --user-data-dir="$tmp/profile" \
    --print-to-pdf="$out/toucan.pdf" "file://$html" 2>/dev/null

echo "Wrote $out/toucan.pdf"
