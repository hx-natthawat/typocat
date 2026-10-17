# Brand

- `mark.svg`: the cat-eared keycap, split into the layout you typed (teal) and the one you meant (marigold). No letters, so it works for every language.
- `app-icon.svg`: the macOS app icon: the mark as a keycap with Manee's eyes on a light plate. `scripts/make-brand-assets.sh` renders it to `Resources/AppIcon.icns`.
- `mark-mono.svg`: one-color menu-bar glyph, the keycap with the eyes cut out. The app draws the same shape in `StatusIcon.swift` as a template image. (A cut-out diagonal looked like a "disabled" slash at 16 pt.)
- `social-preview.png`: 1280×640 banner for GitHub's social preview and link cards, rendered by the same script.
- `manee.svg`: Manee, the mascot. She is a Khao Manee cat with one teal eye and one marigold eye.

Colors: Lagoon `#0B7A75`, Marigold `#F2A12B`, Coral `#E5603D`, Ink `#142220`, Sand `#EEF2EE`.
Fonts: Rubik (wordmark, headings), Noto Sans plus each script's Noto face (text), IBM Plex Mono (keystrokes).
No flags or country colors.
