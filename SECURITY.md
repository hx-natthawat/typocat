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
    With "Match layout to each website" on (off by default), also per-website counts, keyed by
    the host name (`github.com`). Turning the option off deletes them.
  - `learnedWords.json`, only with "Learn words I convert by hand" on (off by default):
    the words you converted by hand with the shortcut, and nothing else you typed. Turning the
    option off deletes the file.
- Keeps in its preferences how many words it fixed into each language: counts only, no words.
- Reads the selected text when you press the convert shortcut with no word typed, to convert
  it. Through Accessibility where the app allows; otherwise it sends ⌘C, reads the copy, and
  restores your clipboard within a fraction of a second. A clipboard manager may still see that
  copy. Converted text with line breaks is pasted, marked as transient so clipboard managers
  skip it, and the clipboard is restored afterwards.
- Reads, with "Match layout to each website" on and a browser in front, the host name of the
  page in the front window through the Accessibility API, once a second. Never page content.
- Pauses in secure input fields such as passwords, and in apps you exclude.

**What it never does**
- No network connections, except when you pick Check for Updates…: that one request asks
  api.github.com for the latest release tag and sends nothing about you or your typing.
  Word lists ship inside the app.
- No logging of typed text, no analytics, no crash reporting.

## Reporting a vulnerability

Please don't open a public issue. Use GitHub's private
[security advisory form](https://github.com/hx-natthawat/typocat/security/advisories/new)
with steps to reproduce. You'll get a reply within a week.
