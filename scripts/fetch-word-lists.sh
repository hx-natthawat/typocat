#!/bin/bash
# Downloads word lists into Data/ (skips ones already there).
# Source: hermitdave/FrequencyWords, content licensed CC BY-SA 4.0.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Data

# Language.bundled: English, non-Latin layouts, and Latin layouts that move letters.
LANGS="${*:-en ru uk bg sr mk kk el he ar fa ur hy ka hi th fr de es it tr cs sv hu da fi}"
BASE=https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
for lang in $LANGS; do
  f="Data/${lang}_50k.txt"
  [ -s "$f" ] && continue
  if curl -fsL -o "$f" "$BASE/$lang/${lang}_50k.txt"; then
    continue
  fi
  # Small corpora only publish a full list; keep its 50k most frequent lines.
  # Download first: piping curl into head fails under pipefail when head stops early.
  if curl -fsSL -o "$tmp" "$BASE/$lang/${lang}_full.txt"; then
    head -n 50000 "$tmp" > "$f"
  else
    rm -f "$f"
    echo "warning: no word list for $lang; its layout won't be detected" >&2
  fi
done
