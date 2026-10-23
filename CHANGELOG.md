# Changelog

## Unreleased

### New
- Korean (2-Set): `dkssudgktpdy` → 안녕하세요 and `ㅗ디ㅣㅐ` → hello. Letters join into syllables the way the input method does. 98.5% of Korean words typed on the English layout are fixed, 99.8% the other way, 0.06% of correct text changed.
- Convert the selection: press the shortcut with nothing typed to convert selected text, a sentence or paragraph at once (`ghbdtn rfr ltkf` → привет как дела). Line breaks are kept.
- Choose the shortcut: ⌃⌥Space, Shift pressed twice, or both.
- Exceptions…: see and edit the words TypoCat never changes and the apps it's off in; add names and brands by hand.
- Each fix flashes the menu bar icon (Show each fix), and VoiceOver reads it aloud.
- The menu shows how many words were fixed into each language. Counts only.
- Learns from wrong fixes noticed late: selecting a fixed word and converting it back, or deleting it and typing it again on the other layout, counts as undoing it.
- Apps where fixes keep being undone get more careful fixes, per language pair; kept fixes slowly win that back. Reset caution from undone fixes in the menu.
- With learning on: undo a typo fix and type the word you meant (`fro` → from, not for), and that's the fix next time.

### Better detection
- A known word is no longer changed into one with a capital inside (`쟤가` → `wOrk`).
- Everyday German and French words the lists lack (`Benutzername`, `Zugangsdaten`, `télétravail`).
- Punctuation keys that type letters on the other layout: Finnish `ty;` → työ, Czech `dom;` → domů, Hungarian `kiss;` → kissé, Finnish `'l'` → älä. Fixed on Finnish 99.2% → 99.8%, Danish 99.1% → 99.7%, Italian 98.0% → 98.8%, Hebrew 94.3% → 95.6%; correct text changed stays the same.

### Fixed
- The setup window reads right to left in Hebrew and Arabic.

## 0.3.0 (2026-10-19)

### New
- Latin layouts: French (AZERTY), German, Czech and Hungarian (QWERTZ), Spanish, Italian, Turkish, Swedish, Danish and Finnish. 98–100% of words typed on the wrong one are fixed.
- Dvorak and Colemak next to QWERTY: a second layout for the same language gets its own entry (`DV`, `CO`) and shares the word list. About 96% fixed, no correct words changed.
- Thai typed in one run is fixed before Space, once the run reads as whole Thai words and can't be the start of an English word.
- The app is translated into Thai, Russian, Ukrainian, German, French, Spanish, Hebrew, Arabic, Greek and Turkish.
- Install with Homebrew: `brew install --cask hx-natthawat/typocat/typocat`.
- Opt-in, off by default, kept on this Mac only:
  - Match layout to each website, in browsers.
  - Learn words you convert with ⌃⌥Space, so they get fixed by themselves next time.

### Better detection
- Short words left alone are reread after a later fix in every language, not only Thai, Russian and Kazakh (35–56% of missed short words recovered elsewhere).
- English typed on the Serbian layout: 78.6% → 82.1% fixed, because English quoted in Serbian subtitles no longer counts as Serbian.
- Everyday words missing from the word lists are added (`ลาย`, `ภาษี`, `สลิป`, `скриншот`, `дедлайн`).
- A known word is no longer changed into one that swaps letters for punctuation (`min` → `;in`, `уж` → `e;`). Correct text changed drops in most languages, for example Hindi 0.11% → 0.03% and Persian 0.07% → 0.00%.
- Digits count inside known words (`1er`, `2nd`).

### Fixed
- The setup window fits its content in every language instead of cutting off long lines.
- A unit test that had failed CI since 0.2.0 (it expected the rarest word in its list to score above the minimum).

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
