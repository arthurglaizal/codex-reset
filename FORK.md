# What this fork changes

Fork of [boyso/codex-reset](https://github.com/boyso/codex-reset), started from
commit `10def85`. Maintained by [Arturo UX](https://github.com/arthurglaizal).

The list below is grouped by what each change answers: **what was broken**,
**what was missing**, and **what moved on screen**. A maintainer looking to pick
things up will care mostly about the first group, which is why it comes first.

---

## Fixed

Bugs present in the original.

- **Paused chats were reported even after being continued.** The query looked
  for each thread's latest usage-limit failure without checking whether
  anything happened afterwards, so a chat resumed by hand stayed listed as
  paused forever. On one real install, 5 of the 17 listed chats were not
  paused at all. The failing turn is now compared against the thread's last
  turn.
- **"Select all" queued chats that did not need it**, including those already
  continued, spending usage for nothing.
- **The menu bar reported usage spent while Codex reports quota left**, showing
  `0%` on a full quota. Both now agree, and the ring drains instead of filling.
- **The status dot only watched the 5-hour window.** With the weekly quota at
  5% it stayed green, although nothing could run. It now reflects the worse of
  the two windows.
- **The settings window was unreadable in dark mode.** The palette is
  hard-coded light, and that window was missing the color scheme the main panel
  already pinned, so labels rendered white on white.
- **System notifications were hard-coded in Chinese** and never went through
  the translation helper, so an English user got Chinese alerts.
- **A crash left `codex app-server` processes running forever**, holding the
  write lock on the thread database. The startup guard ran a blind
  `pkill -f "app-server --listen"`, which would also kill a server started by
  another tool. The spawned server's PID is now recorded and only that process
  is cleaned up, after verifying its command line.
- **Fallback titles showed a generated context block.** When a chat has no
  usable title, the first user message is used instead, and Codex prefixes
  messages carrying attachments with a `# Files mentioned by the user:` block
  followed by file paths. Several unrelated chats therefore appeared under the
  same name. That block is now skipped, falling back to a file count when the
  message contains nothing else.

## Added

Features the original does not have.

- **Resume every paused chat without ticking anything.** Auto-continue now has
  a scope: the chats you ticked, or every chat still paused. The zero-effort
  case no longer requires going through the list at each reset.
- **Ignore a chat.** It leaves every list for a collapsed section and can never
  be resumed, automatically or manually. This is what makes the previous
  feature usable: exclude once what you never want relaunched.
- **Search** across chat titles and project paths, in each list.
- **A countdown to the next 5-hour reset**, which reads differently depending
  on whether it unblocks anything: orange with an hourglass when the quota is
  spent, grey with a clock otherwise.
- **Turn count per chat**, to tell a long session from one that stopped at its
  first exchange.
- **An "Already continued" list**, kept for checking that the detection above
  is not discarding chats it should not.
- **A detail card** with the full title, which the list elides. It opens from
  an info icon on the row rather than on hovering the row itself, so reaching
  for a check box does not cover the list.
- **Dark mode**, on by default, switchable in the settings window.

## Changed

Same behaviour, different presentation.

- The panel is 880pt wide and split in two columns: chat lists on the left,
  automation and quota on the right.
- The four lists (paused, ignored, already continued, all chats) are
  accordions, one open at a time, the open one taking all remaining height
  instead of scrolling inside 160pt.
- Quota is shown as **what is left**, as vertical gauges, green through orange
  to red, matching Codex's own wording.
- Each chat is a card with a status chip, rather than a row with a loose icon
  and a right-aligned time.
- The tab picker moved into the title bar, which now shows the app name; the
  connection and accessibility states moved to a "Configuration" footer, where
  a missing accessibility grant is stated as optional rather than drawn as a
  warning.
- The wording is uniform: everything says "paused", not a mix of paused and
  stuck.

## Not touched

The parts that carry the risk are untouched: the app-server protocol client,
the WebSocket transport, the GUI fallback, and the auto-continue engine itself.
Changes are concentrated in the SQLite reader, the views, and the process
lifecycle fix above.

---

## Picking these up

No pull request is open. To take any of this:

```bash
git remote add arturo https://github.com/arthurglaizal/codex-reset.git
git fetch arturo
git log arturo/main
```

Each change is a separate commit with its reasoning in the message. The
detection fix and the orphan-server fix stand on their own and do not depend on
any of the interface work.
