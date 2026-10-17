# Changelog

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
