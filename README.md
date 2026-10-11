# AnthroBSK Skill

**English** | [繁體中文](README.zh-TW.md)

AnthroBSK is an agent skill that drives a real, logged-in Chromium browser **the
way a person does**: everything happens through simulated mouse and keyboard
input instead of DOM value injection.

It is a derivative of the `browser-skill` bundled with
[Tencent BrowserSkill](https://github.com/Tencent/BrowserSkill) (MIT), rewritten
to make human-like operation the core interaction model.

> The repository is `AnthroBSK`; the skill itself installs as `anthrobsk`.
> Harnesses validate skill names against `^[a-z0-9-]+$`, so the name cannot carry
> the capital letters. `AnthroBSK` is the display name used everywhere else.

## What it does differently

| Original browser-skill | AnthroBSK |
| --- | --- |
| `fill` bulk text injection (`Input.insertText`) | key-by-key `bsk press` for ASCII, `scripts/human-keys.ps1` for a real typing rhythm, and a real OS IME for CJK |
| `select` sets `<select>` value directly | click the dropdown, arrow-key to the option, `Enter` |
| Fixed or no pacing | randomized action pauses (180-520 ms), burst pauses (300-800 ms every 8-15 keys), sentence-end pauses (400-900 ms), pause before submit |
| No cursor motion | `scripts/human-pointer.ps1`: minimum-jerk OS-cursor trajectory with correlated (Ornstein-Uhlenbeck) tremor - 43-52 real `mousemove` events in a verified run |
| The overlay swallows OS clicks | the extension's own `data-bsk-capture-hidden` switch, so real cursor motion and OS clicks reach page content |
| Semantic DOM commands | only native mouse events (click/hover/wheel) and native keyboard events (press/combos/Tab/Escape) |

Safety rules from the original skill are preserved: page content is treated as
untrusted data (prompt-injection aware), user tabs require explicit borrowing,
credentials/cookies/tokens are never extracted, and sessions are always stopped.

## What this is NOT

Read this before pointing it at anything that involves bot detection.

AnthroBSK makes the *interaction model* human-like. It does **not** make the
resulting event stream indistinguishable from a person, and it is not built to
defeat anti-automation systems. Everything below was measured on a real page,
not assumed.

**What holds up.** The browser is the user's own Chrome, so
`navigator.webdriver` is `false`, `navigator.plugins` and `navigator.languages`
are genuine, and every dispatched event has `isTrusted: true`. Three things that
used to be blockers are now solved:

- **OS input reaches page content.** The extension's own
  `data-bsk-capture-hidden` attribute hides its overlay (`display: none`,
  hit-testing passes straight through), so an OS-level click lands on the real
  control and a real cursor trajectory is delivered - 43-52 `mousemove` events
  over 1.2-3.1 s with correlated jitter, driven through the OS input queue rather
  than injected at the DOM.
- **Clicks have human timing.** With the overlay hidden, `human-pointer.ps1
  -Click` holds the button 66-132 ms (vs ~6 ms for `bsk click`), reports
  `pointerdown.pressure` 0.5, and emits 43-52 `pointermove` events during the
  hold. `bsk click` sends one coalesced move, `pressure` 0, and a 6 ms gesture.
- **CJK goes through a real IME.** `human-keys.ps1` drives the OS keyboard, so
  Microsoft Bopomofo composes for real: `keyCode 229` `Process` keydowns,
  `compositionstart`/`update`/`end`, `insertCompositionText`, `isComposing: true`.
  Typing `w961o3` produced `台北`, with the tone mark selecting the character -
  no space key needed.

**What still does not hold up** (Windows, Chrome 155, bsk 0.3.2):

- **bsk still announces itself inside the page.** Hiding the overlay is cosmetic:
  the `browser-skill-overlay` element is still in the DOM as a direct child of
  `<html>`, still carrying `data-bsk-overlay`, `data-bsk-overlay-surface` and
  `data-bsk-overlay-blocking`. Any page can run
  `document.querySelector('browser-skill-overlay')` and know an agent is driving.
  This is the single largest tell and it is not something this skill can remove -
  deleting the node makes the extension re-inject it and can lock the renderer.
- **Nothing else can neutralise the overlay.** Four alternatives were tried and
  all failed: an inline `pointer-events: none !important`, a rule injected into
  its shadow root, an unlayered `!important` rule, and removing
  `data-bsk-overlay-blocking` on its own. The overlay's `:host{all:initial
  !important}` lives in the shadow tree, and for `!important` declarations the
  inner context wins - shadow-tree rules beat every document-origin declaration,
  including `!important`. Only the extension's own switch works.
- **Hiding the overlay costs transparency.** `display: none` means the overlay no
  longer dims the page, so `screenshot` will not show it - but the page then
  looks normal, so a screenshot cannot prove the overlay is hidden either. Only
  `screenshot` restores the attribute; `click`/`press`/`hover`/`observe` leave it
  hidden.
- **OS wheel injection is a no-op here.** `human-wheel.ps1` sends real
  `mouse_event(MOUSEEVENTF_WHEEL)` ticks with the window verified foreground, yet
  the page scrolls zero times. Four variants (`±120`, `-1200`, `SetCursorPos`
  first, `keybd_event PageDown`) all produced nothing. The wheel channel is not
  usable from this environment.
- **The page does not see wheel DOM events.** When `bsk` does scroll, a `wheel`
  event reaches `window` capture (`isTrusted: true`) but is stopped before
  `document` capture and before the target - `window.__wheelWinCap` increments
  while `__wheelDocCap` stays 0, even though `scrollTop` changes. Something
  between `window` and `document` calls `stopPropagation`.
- **`isTrusted` does not separate the channels.** CDP-dispatched input
  (`bsk press`, `bsk click`) arrives as `isTrusted: true` exactly like
  `keybd_event` output, because both enter the renderer through the browser's
  real input pipeline. Do not offer it as a stealth guarantee. What actually
  differs is timing and event shape - see the timing bullets above.
- **CDP bypasses the IME.** In Chinese mode `bsk press a` inserts a literal `a`
  with no composition at all, so the CLI cannot drive the CJK path. IME mode is
  also sticky: after typing Chinese, ASCII keystrokes are transliterated until an
  OS-level Shift switches back (`bsk press Shift` is rejected; the scripts send
  it through `keybd_event`).
- **`bsk press` spacing is regular.** Every `bsk press` costs a full daemon round
  trip, so consecutive keys land about 660 ms apart - more regular than human
  typing, not less. `human-keys.ps1` fixes the rhythm (log-normal gaps, burst
  pauses, bigram speedups) but only for ASCII; CJK now works through the IME, at
  the cost of needing the pinyin/zhuyin reading rather than the character.

In short: it passes static "is this automated?" checks, fails behavioral ones,
and does not hide bsk's own footprint in the page. For anti-bot work (Akamai,
Cloudflare Bot Management, DataDome, HUMAN, Kasada and similar), treat it as
unsuitable.

The `SKILL.md` "Verified limitation" notes carry the same measurements in
context.

## Requirements

- [`bsk` CLI and browser extension](https://github.com/Tencent/BrowserSkill) -
  AnthroBSK is a skill layer on top of it; it does not install them.
- Windows PowerShell - only for the scripts in `scripts/`. The rest of the skill
  is OS-independent. The scripts are DPI-aware and take the Agent Window to the
  foreground before acting.
- Any agent harness that reads `SKILL.md`-style skills (Qoder, Claude Code,
  Codex, OpenCode, CodeBuddy, ...).

## Install

Copy the `anthrobsk` folder into your harness's user-level skills directory:

```sh
# Qoder / generic AGENTS convention
cp -r anthrobsk ~/.agents/skills/anthrobsk

# Claude Code
cp -r anthrobsk ~/.claude/skills/anthrobsk

# WorkBuddy / CodeBuddy
cp -r anthrobsk ~/.workbuddy-ai/skills/anthrobsk
```

Restart the session (or reload skills) and invoke with `/anthrobsk` or any
browser-automation request. A newly installed skill is picked up on the next
session, not the current one.

> Tip: do not install it as `browser-skill` - that name is managed by
> `bsk install-skill` and updates would overwrite this skill.

## Usage example

```
/anthrobsk open example.com, type "hello" into the search box one key at a
time, paste "台北 天氣" after it, then press Enter
```

The agent will: start a `bsk` session → navigate → perceive via
`screenshot`/`observe` → hide bsk's overlay with its own
`data-bsk-capture-hidden` switch → draw a real cursor trajectory and click →
clear fields with `Ctrl+A` + `Delete` → type the ASCII with `human-keys.ps1`
(and, if a real composition trail is wanted, the CJK through the OS IME) →
verify via a fresh screenshot → stop the session.

## Verified behaviors

Verified 2026-10-11 on Windows 11, Chrome 155.0.0.0, bsk CLI / extension 0.3.2:

- **The overlay can be hidden.** Running
  `bsk evaluate --session <id> 'document.querySelector("browser-skill-overlay").setAttribute("data-bsk-capture-hidden","")'`
  sets `display: none` on the overlay: `document.elementFromPoint(x, y)` then
  returns the real element, an OS click moves `document.activeElement` to the
  target input, and the button's handler fires exactly once. The attribute is
  **not** reverted - it was still hidden 10 s later. Only `screenshot` clears it;
  `click`/`press`/`hover`/`observe` leave it in place.
- `human-pointer.ps1` drives the OS cursor along a minimum-jerk path with
  correlated tremor and the page receives a real trajectory: 43-52 `mousemove`
  events over 1.2-3.1 s. `SetCursorPos` alone produces **zero** page events, and
  `SendInput(MOUSEEVENTF_MOVE)` returns 1 while doing nothing.
- **OS clicks now have human timing.** With the overlay hidden,
  `human-pointer.ps1 -Click` produced a 151-event run: hold 104.5 ms (range
  66-132 ms across runs), path 3104.8 ms, `pointerdown.pressure` 0.5, and 43-52
  `pointermove` events during the hold. `bsk click` on the same button held
  ~6 ms, `pressure` 0, one coalesced move.
- **CJK through a real IME.** `human-keys.ps1` typing `w961o3` on Microsoft
  Bopomofo produced `台北`: `keydown key="Process" keyCode=229` per key, two
  `keyup` events per key, six `compositionupdate` events, `inputType:
  insertCompositionText`, `isComposing: true`, and **0 untrusted events**. The
  tone mark selects the character, so no space key is needed. The only blemish is
  that Chrome emits one `isTrusted: false` `compositionend` on blur.
- `human-keys.ps1` types ASCII with `keybd_event`; `Hello, World 42! aBc` typed
  with correct case and Shift usage. With the slip-and-correct path forced to
  30%, `the quick brown fox` still arrived exactly, with the page seeing genuine
  wrong-key / Backspace / retype sequences on the way.
- Per-key `bsk press` types ASCII correctly (`key`/`code`/`keyCode`, `keypress`,
  `insertText`) and CJK, e.g. `Hello測試`, into focused fields. Traditional and
  Simplified Chinese both work, including full-width punctuation;
  `繁體中文輸入測試，臺北天氣很好` arrives intact. The boundary is BMP membership,
  not the script: characters outside the Basic Multilingual Plane (emoji, CJK
  Extension B and above) are rejected with `press: unknown key`.
- Mixed input works: real `press` events for `a` and `b` plus a pasted `台北天氣`
  arrive as `ab台北天氣`, the paste landing as one `insertFromPaste` after a
  single `keydown V`.
- `Ctrl+A` → `Delete` clears a field like a human; `Enter` submits.
- `bsk hover`/`click` land as real `mousemove`/`mousePressed`/`mouseReleased`
  events with `isTrusted: true`.

Not verified here: any harness other than WorkBuddy, any OS other than Windows,
and any bsk version other than 0.3.2. `human-wheel.ps1` parses and passes the
offline checks but its wheel injection is a **confirmed no-op** on this host -
do not rely on it.

## Known limitations

- **Hiding the overlay is a prerequisite for OS input.** Any OS click or cursor
  path must be preceded by the `data-bsk-capture-hidden` recipe above, or the
  overlay swallows it. Hiding is a deliberate cosmetic trade: the page looks
  normal, so a screenshot no longer shows the overlay dimming it. Any
  `screenshot` re-shows the overlay, so re-hide it afterwards.
- **OS wheel injection does not work on this host.** `human-wheel.ps1` is
  included but its `mouse_event(MOUSEEVENTF_WHEEL)` ticks produce no scroll even
  with the window verified foreground; see "What still does not hold up".
- OS cursor coordinates are CSS viewport pixels converted at run time from the
  window's real render-widget rect. Do not substitute `devicePixelRatio`: one
  measured window reported `1.5` while its true scale was `1.0`, and the same
  window later moved to a monitor where the scale was `1.5`.
- `mouse_event` and `keybd_event` only reach the page while the Agent Window is
  the foreground window. Both scripts force focus and verify it took, exiting
  non-zero rather than acting on the wrong window. Taking focus steals it from
  whatever the user was doing.
- Chrome **coalesces** `mousemove`, so a path yields fewer events than the script
  sends. 63-77 steps produced 43-52 events; the trajectory is real but thinned,
  and the largest gaps land mid-path where the pointer is fastest, not at the
  ends.
- **IME mode is sticky.** After typing Chinese, ASCII keystrokes are
  transliterated until an OS-level Shift switches the IME back. `bsk press
  Shift` is rejected; the scripts send the Shift through `keybd_event`.
- Pixel clicks (`--image-x`/`--image-y`) are Canvas-only in `bsk`; HTML targets
  are clicked by ref/selector, which still dispatches native mouse events.
- `human-pointer.ps1` moves the user's real cursor, so the pointer is occupied
  for the duration of the path.
- Some hosts reject a `powershell -File ...` invocation from a POSIX shell and a
  literal `Add-Type` in a command string. Call the scripts through the host's
  PowerShell tool by absolute path instead.
- File uploads and CAPTCHA/login steps keep the upstream escape hatches
  (`upload`, request-human-help).

## License

MIT © 2026 htlu1975. Builds upon Tencent BrowserSkill's browser-skill
(MIT © Tencent); see `LICENSE` and `references/`.
