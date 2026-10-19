# Changelog

## 0.2.0 (2026-10-19)

First release with a download: open `TypoCat.dmg` and drag TypoCat into Applications.

### New
- Setup window on first launch, and from the menu (Setup…): Accessibility access with live status, your keyboards, a field to try a fix, and the main options. Light and dark mode.
- Check for Updates… in the menu. It's the app's only network request, made only when you pick it.
- Drag-to-Applications installer with a background that explains the first-open steps.
- New look: a cute 3D Manee app icon, a cat-head menu-bar glyph that dims when TypoCat is off, a social preview banner and a README animation.

### Faster and lighter
- Word lists are compiled at build time and mapped from disk: they load in under 10 ms instead of 0.6–2.7 s, and the app uses 14 MB with English + Thai (was 19–21 MB).

### Better detection
- Keys that type punctuation in English but letters elsewhere (`[kp` is บาย, `=kp` is ชาย) no longer hide a wrong-layout word: 1–4 points more words fixed in most languages (Thai 96.0% → 98.4%, Persian 93.2% → 96.6%, Hindi 92.7% → 95.0%), with no more correct text changed.
- Russian and Kazakh reread short words once a later word is fixed (`lf ghbdtn` → `да привет`), as Thai does: 85% and 79% of missed short words recovered.
- A one-key word before a fixed word is taken back when it is I or i ("ณ love" → "I love").
- Electron apps (VS Code and others) are asked to expose their text fields, so TypoCat can check them before a fix.

### Fixed
- English in single quotes ('to', 'a') was changed to Hebrew or Arabic, where the ' key types a letter.
- In zsh (tested in Terminal and Ghostty), hello typed on the Thai layout (้ำสสน) wasn't fixed: zsh shows the leading tone mark as `<0e49>`.
- Nothing was fixed in Ghostty, which reports the text cursor at the start of the screen.
- A wrong-layout word starting with a Thai tone or vowel mark was skipped right after a space.
- Fast typing: keys typed while a fix is being written are held and replayed in order, and the field check waits up to 120 ms for the app to catch up.

### For developers
- Pushing a `v*` tag builds `TypoCat.dmg` on GitHub Actions and attaches it to a release.
- `scripts/make-signing-cert.sh` creates a local signing certificate that `build-app.sh` uses, so Accessibility access survives rebuilds.
- `--eval` checks English with ordinary punctuation, and `LS_REREAD_ALL=1 --eval` measures rereading for every language. Results are the same on every run.

## 0.1.0 (2026-10-17)

First open-source release. Build from source; no signed binary yet.

- Fixes words typed on the wrong keyboard layout and switches the layout. Works with any macOS layout that has a word list: 15 languages plus English, measured in the README.
- Thai and other scripts without spaces: short words are reread once a later word is fixed.
- Dead keys (Greek accents) and Serbian Latin/Cyrillic word lists.
- Checks the focused field through Accessibility before rewriting; undo with Backspace or ⌘Z.
- Protects tech words, and shell commands in terminals and editors.
- Per-app exclusion, per-app language memory, open at login.
- Typo correction (beta, off by default), checked against the macOS spell checker. English and Russian only for now.
- `--selftest`, `--eval` and `--eval-typos` measure accuracy on any Mac.
