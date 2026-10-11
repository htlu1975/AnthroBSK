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
| `fill` bulk text injection (`Input.insertText`) | key-by-key `bsk press` for ASCII, `scripts/human-keys.ps1` for a real typing rhythm, clipboard paste for CJK |
| `select` sets `<select>` value directly | click the dropdown, arrow-key to the option, `Enter` |
| Fixed or no pacing | randomized action pauses (180-520 ms), longer "thinking" pauses (700-2000 ms), pause before submit |
| No cursor motion | `scripts/human-pointer.ps1`: cubic-Bezier OS-cursor trajectory the page actually observes - 54 real `mousemove` events in a verified run |
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
are genuine, and every dispatched event has `isTrusted: true`. A real cursor
trajectory is genuinely delivered too - 54 `mousemove` events over about 1.2 s
with 2-22 px deltas and 5-49 ms jitter, driven through the OS input queue rather
than injected at the DOM.

**What does not hold up** (Windows, Chrome 155, bsk 0.3.2):

- **bsk announces itself inside the page.** The extension injects a
  `browser-skill-overlay` element into the page's main world: `position: fixed`,
  `z-index: 2147483647`, covering the viewport, carrying `data-bsk-overlay`,
  `data-bsk-overlay-surface` and `data-bsk-overlay-blocking` attributes. Any page
  can run `document.querySelector('browser-skill-overlay')` and know an agent is
  driving. This is the single largest tell and it is not something this skill can
  hide.
- **OS-level clicks cannot reach page content.** That same overlay has
  `pointer-events: auto`, so `document.elementFromPoint(x, y)` returns
  `BROWSER-SKILL-OVERLAY` and the real control receives no `mousedown`/`click`.
  Measured on a GitHub upload page, the overlay's bounding rect was exactly the
  viewport (`0,0 1707x769`) and sampling two separate points - a text input and
  a submit button - returned `BROWSER-SKILL-OVERLAY` at both. An OS-level click
  aimed at the input moved the cursor to the correct physical pixel and held the
  button for 95 ms, yet focus never moved: the click was swallowed end to end.
  Neutralising the overlay does not work: it is re-injected automatically, and
  its `:host{all:initial !important}` sits inside a CSS `@layer`, so both an
  inline `pointer-events: none !important` and a rule injected into its shadow
  root lose the cascade (unlayered `!important` is the weakest kind). Clicks
  therefore have to go through `bsk click`, which targets the element directly.
- **The overlay blocks the mouse but not the keyboard.** Keystrokes go to
  whatever element holds focus and never traverse hit-testing, so OS-level
  typing is unaffected. This gives the practical recipe: focus the field with
  `bsk click --selector '<css>'`, then type with real `keybd_event` keystrokes.
  A live run on a GitHub commit form produced **265 events, 100% `isTrusted:
  true`, 0 untrusted**, including two genuine slip-and-fix corrections
  (`fal`+`r` → Backspace → `l`, and `bac`+`t` → Backspace → `k`) that still left
  the field holding exactly the intended text.
- **`isTrusted` does not separate the channels.** CDP-dispatched input
  (`bsk press`, `bsk click`) arrives as `isTrusted: true` exactly like
  `keybd_event` output, because both enter the renderer through the browser's
  real input pipeline. Do not offer it as a stealth guarantee. What actually
  differs is timing and event shape - see the timing bullets below.
- **Click timing.** One `bsk click` reaches the page as a single `mousemove`,
  then `mousedown` 2-4 ms later, then `mouseup` 0.8-2 ms after that - roughly
  6 ms for the whole gesture. A human holds the button 60-120 ms after moving for
  80-300 ms. The `pointermove` carries one coalesced event and `pressure` stays
  `0` while a button is down. `bsk click` exposes no hold-duration or pre-move
  option, so the skill layer cannot close this.
- **Input-method events.** Typed characters are CDP `char` events. For CJK the
  page sees `code: ""`, `keyCode: 0`, and a `keypress.keyCode` equal to the
  character's code point rather than a virtual key code. No
  `compositionstart`/`compositionupdate`/`compositionend` is emitted and
  `isComposing` stays `false`, so a page can tell the text did not come from a
  real IME (which emits `insertCompositionText` with `keyCode: 229` during
  composition). OS-level keystrokes do not close this either - driving a real IME
  means selecting candidates, and the layout handle resolves to `0x0` in this
  context so character translation is unreliable. The skill pastes CJK instead,
  which yields a genuine `insertFromPaste`, but a paste is still a paste.
- **ASCII key spacing through the CLI.** Every `bsk press` costs a full daemon
  round trip, so consecutive keys land about 660 ms apart - more regular than
  human typing, not less. `scripts/human-keys.ps1` fixes the rhythm (about
  190-230 ms per key with jitter) but only for ASCII.

In short: it passes static "is this automated?" checks, fails behavioral ones,
and does not hide bsk's own footprint in the page. For anti-bot work (Akamai,
Cloudflare Bot Management, DataDome, HUMAN, Kasada and similar), treat it as
unsuitable.

The `SKILL.md` "Verified limitation" notes carry the same measurements in
context.

## Requirements

- [`bsk` CLI and browser extension](https://github.com/Tencent/BrowserSkill) -
  AnthroBSK is a skill layer on top of it; it does not install them.
- Windows PowerShell - only for the two scripts in `scripts/`. The rest of the
  skill is OS-independent. Both scripts are DPI-aware and take the Agent Window
  to the foreground before acting.
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
`screenshot`/`observe` → draw a real cursor trajectory and click → clear fields
with `Ctrl+A` + `Delete` → type the ASCII with `human-keys.ps1` and paste the CJK
→ verify via a fresh screenshot → stop the session.

## Verified behaviors

Verified 2026-10-11 on Windows 11, Chrome 155.0.0.0, bsk CLI / extension 0.3.2:

- `human-pointer.ps1` drives the OS cursor along a randomized Bezier and the
  page receives a real trajectory: 54 `mousemove` events over ~1.2 s, deltas
  varying 2-22 px, samples 5-49 ms apart. `SetCursorPos` alone produces **zero**
  page events, and `SendInput(MOUSEEVENTF_MOVE)` returns 1 while doing nothing.
- `human-keys.ps1` types ASCII with `keybd_event`; `Hello, World 42! aBc` typed
  as 191 ms/char with correct case and Shift usage. With the slip-and-correct
  path forced to 30%, `the quick brown fox` still arrived exactly, with the page
  seeing five genuine wrong-key / Backspace / retype sequences on the way.
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
and any bsk version other than 0.3.2.

## Known limitations

- OS cursor coordinates are CSS viewport pixels converted at run time from the
  window's real render-widget rect. Do not substitute `devicePixelRatio`: one
  measured window reported `1.5` while its true scale was `1.0`, and the same
  window later moved to a monitor where the scale was `1.5`.
- `mouse_event` and `keybd_event` only reach the page while the Agent Window is
  the foreground window. Both scripts force focus and verify it took, exiting
  non-zero rather than acting on the wrong window. Taking focus steals it from
  whatever the user was doing.
- Chrome **coalesces** `mousemove`, so a path yields fewer events than the script
  sends. 140 steps produced 54 events; the trajectory is real but thinned.
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
