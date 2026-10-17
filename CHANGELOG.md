# Changelog

## Unreleased

- Word lists use about a third of the memory: 7 languages at 25 MB instead of 59 MB, and they load faster. Detection results are unchanged.
- Keys typed while a fix is being written are held and replayed in order.
- Electron apps (VS Code and others) are asked to expose their text fields to Accessibility.
- Ranks no longer depend on dictionary order, so `--eval` gives the same numbers on every run.

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
