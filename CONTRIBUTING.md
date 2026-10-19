# Contributing to TypoCat

Thanks for helping. TypoCat watches people's keyboards, so the bar is
simple: never make it worse at leaving correct text alone.

## Setup

```bash
git clone https://github.com/hx-natthawat/typocat.git && cd typocat
./scripts/fetch-word-lists.sh      # word lists into Data/ (not committed)
swift build
swift run TypoCat --selftest       # uses every layout installed on your Mac
swift test                         # unit tests; needs Xcode, not just the Command Line Tools
```

To try the app: `./scripts/build-app.sh && open build/TypoCat.app`, then
grant Accessibility access. Ad-hoc builds lose that access on every rebuild;
set `SIGN_IDENTITY` to a code-signing certificate to keep it.

## Code layout

| Path | Contents |
|---|---|
| `Sources/TypoCatCore` | Pure logic, no AppKit: layouts, word lists, scoring, typo fixes. Put anything testable here. |
| `Sources/TypoCat` | The app: event tap, input sources, Accessibility checks, menu, settings, `--selftest` / `--eval`. |
| `Tests/TypoCatCoreTests` | Unit tests with small synthetic layouts and word lists. |

## Changing detection

Every change to scoring or thresholds needs numbers. Run before and after,
and paste both into the pull request:

```bash
swift build -c release
.build/release/TypoCat --eval 5000         # layout fixes, every bundled language
.build/release/TypoCat --eval-typos 5000   # typo fixes
```

"Correct text changed" is the column that matters most. A change that fixes
more words but changes more correct text needs a strong argument.

## Adding a language

1. Check that macOS has a keyboard layout for it (`--eval` lists installed ones)
   and that [FrequencyWords](https://github.com/hermitdave/FrequencyWords) has a list.
2. Add its ISO 639-1 code to `Language.bundled` (`Sources/TypoCatCore/Layout.swift`)
   and to `LANGS` in `scripts/fetch-word-lists.sh`.
3. If it's written without spaces, add it to `Language.writesWithoutSpaces`.
4. Add a few everyday words to the cases in `Sources/TypoCat/SelfTest.swift`.
5. Run `--selftest` and `--eval 5000`, and add its row to the README table.
   `LS_LANGS=xx --eval 5000` measures it before it's bundled, and
   `LS_SHOW_CHANGED=1` lists the correct words it changes.
6. Everyday words the list lacks go in `Data/extra/<code>.txt`, one per line.

Latin layouts work the same way; only words that use moved keys are measured.
A second layout for a language (Dvorak) needs nothing: it becomes `en+dvorak`
when its letters differ from the first one's.

Input methods (Japanese, Chinese, Korean) have no key map and can't work this way.

## Translations

User-facing text is English in the source, and `Resources/<code>.lproj/Localizable.strings`
maps it to each language (keys are the English text; `%@` and `%1$@` are filled in). To add a
language, copy an existing file, translate the right-hand sides, then check the setup window:

```bash
./scripts/build-app.sh
build/TypoCat.app/Contents/MacOS/TypoCat --render-setup /tmp/setup.png -AppleLanguages '(xx)'
```

Thai fixed before Space has its own measure: `--eval-midword 3000`.

## Style

Match the surrounding code: small types, comments that say *why*, user-facing
text written for people (say what happened and how to undo it).

## Privacy rules for code

- Never log, store or send typed text. The only persisted words are ones the
  user explicitly undid (`ignoredWords.json`).
- No network access in the app.
- Respect secure input (password fields) and excluded apps.
