# Security and privacy

TypoCat needs Accessibility access because it reads keystrokes to spot words
typed on the wrong layout. That is a lot of trust, so here is exactly what it does.

**What it does**
- Keeps the current word in memory as key codes, and drops it at the next
  word, click, app switch or shortcut.
- Reads the focused text field (Accessibility API) only to check that the
  field ends with the word it is about to fix.
- Saves on disk, in `~/Library/Application Support/TypoCat/`:
  - `ignoredWords.json`: words you undid.
  - `appLanguageCounts.json`: per-app counts of which language you typed. Counts only, no text.
- Pauses in secure input fields such as passwords, and in apps you exclude.

**What it never does**
- No network connections. Word lists ship inside the app.
- No logging of typed text, no analytics, no crash reporting.

## Reporting a vulnerability

Please don't open a public issue. Use GitHub's private
[security advisory form](https://github.com/hx-natthawat/typocat/security/advisories/new)
with steps to reproduce. You'll get a reply within a week.
