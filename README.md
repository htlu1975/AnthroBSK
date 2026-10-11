# AnthroBSK Skill

**English** | [繁體中文](README.zh-TW.md)

AnthroBSK is an agent skill that drives a real, logged-in Chromium browser **the
way a person does**: everything happens through simulated mouse and keyboard
input instead of DOM value injection.

It is a derivative of the `browser-skill` bundled with
[Tencent BrowserSkill](https://github.com/Tencent/BrowserSkill) (MIT), rewritten
to make human-like operation the core interaction model.

## What it does differently

| Original browser-skill | AnthroBSK |
| --- | --- |
| `fill` bulk text injection (`Input.insertText`) | key-by-key `bsk press`, ASCII **and CJK verified**, with randomized per-key pauses |
| `select` sets `<select>` value directly | click the dropdown, arrow-key to the option, `Enter` |
| Fixed or no pacing | randomized action pauses (180-520 ms), longer "thinking" pauses (700-2000 ms), pause before submit |
| No cursor motion | `scripts/human-pointer.ps1`: cubic-Bezier OS-cursor trajectory with easing, jitter, overshoot-and-correct, and random micro-pauses |
| Semantic DOM commands | only native mouse events (click/hover/wheel) and native keyboard events (press/combos/Tab/Escape) |

Safety rules from the original skill are preserved: page content is treated as
untrusted data (prompt-injection aware), user tabs require explicit borrowing,
credentials/cookies/tokens are never extracted, and sessions are always stopped.

## What this is NOT

Read this before pointing it at anything that involves bot detection.

AnthroBSK makes the *interaction model* human-like. It does **not** make the
resulting event stream indistinguishable from a person, and it is not built to
defeat anti-automation systems. The limitations below were measured on a real
page, not assumed.

**What holds up.** The browser is the user's own Chrome, so
`navigator.webdriver` is `false`, `navigator.plugins` and `navigator.languages`
are genuine, and every dispatched event has `isTrusted: true`. Checks of the
form "is an automation framework driving this browser?" pass.

**What does not hold up** (Windows, Chrome 155, bsk 0.3.2):

- **Click timing.** One `click` reaches the page as a single `mousemove`, then
  `mousedown` 2-4 ms later, then `mouseup` 0.8-2 ms after that - roughly 6 ms
  for the whole gesture. A human holds the button 60-120 ms after moving for
  80-300 ms. The `pointermove` carries one coalesced event, and `pressure` stays
  `0` while a button is down. `bsk click` exposes no hold-duration or pre-move
  option, so the skill layer cannot close this.
- **Input-method events.** Typed characters are CDP `char` events. For CJK the
  page sees `code: ""`, `keyCode: 0`, and a `keypress.keyCode` equal to the
  character's code point rather than a virtual key code. No
  `compositionstart` / `compositionupdate` / `compositionend` is emitted, and
  `isComposing` stays `false`. A page can therefore tell that CJK text did not
  come from a real IME, which normally produces `insertCompositionText` with
  `keyCode: 229` during composition.
- **Pacing.** Every `bsk` call starts a process and costs about 0.9-1.2 s, which
  dominates the per-key pauses. Measured inter-key intervals land within a few
  percent of each other - more regular than human typing, not less.
- **Cursor trajectory.** Chrome coalesces `mousemove`, so a long OS-cursor path
  usually arrives as only its final point.

In short: it passes static "is this automated?" checks and fails behavioral
ones. For anti-bot work (Akamai, Cloudflare Bot Management, DataDome, HUMAN,
Kasada and similar), treat it as unsuitable.

The `SKILL.md` "Verified limitation" notes carry the same measurements in
context.

## Requirements

- [`bsk` CLI and browser extension](https://github.com/Tencent/BrowserSkill) -
  AnthroBSK is a skill layer on top of it; it does not install them.
- Windows PowerShell (only for `scripts/human-pointer.ps1`; the rest of the
  skill is OS-independent).
- Any agent harness that reads `SKILL.md`-style skills (Qoder, Claude Code,
  Codex, OpenCode, CodeBuddy, ...).

## Install

Copy the `anthro-bsk` folder into your harness's user-level skills directory:

```sh
# Qoder / generic AGENTS convention
cp -r anthro-bsk ~/.agents/skills/anthro-bsk

# Claude Code
cp -r anthro-bsk ~/.claude/skills/anthro-bsk

# WorkBuddy / CodeBuddy
cp -r anthro-bsk ~/.workbuddy-ai/skills/anthro-bsk
```

Restart the session (or reload skills) and invoke with `/anthro-bsk` or any
browser-automation request. A newly installed skill is picked up on the next
session, not the current one.

> Tip: do not install it as `browser-skill` - that name is managed by
> `bsk install-skill` and updates would overwrite this skill.

## Usage example

```
/anthro-bsk open example.com, type "台北 天氣" into the search box character by
character, then press Enter
```

The agent will: start a `bsk` session → navigate → perceive via
`screenshot`/`observe` → hover/click with native mouse events → clear fields
with `Ctrl+A` + `Delete` → type with per-key `bsk press` and randomized pauses
→ verify via a fresh screenshot → stop the session.

## Verified behaviors

Verified 2026-10-11 on Windows 11, Chrome 155.0.0.0, bsk CLI / extension 0.3.2:

- Per-key `bsk press` types ASCII and CJK (e.g. `Hello測試`) into focused fields.
- Traditional and Simplified Chinese both work, including full-width
  punctuation; `繁體中文輸入測試，臺北天氣很好` typed character by character arrives
  intact. The boundary is BMP membership, not the script: characters outside the
  Basic Multilingual Plane (emoji, CJK Extension B and above) are rejected with
  `press: unknown key`.
- `Ctrl+A` → `Delete` clears a field like a human; `Enter` submits.
- `bsk hover`/`click` land as real `mousemove`/`mousePressed`/`mouseReleased`
  events with `isTrusted: true`.
- `human-pointer.ps1` moves the OS cursor along a randomized Bezier and reports
  `ok path=(x,y)->(x,y) steps=N ms=T`.

Not verified here: any harness other than WorkBuddy, any OS other than Windows,
and any bsk version other than 0.3.2.

## Known limitations

- Chrome **coalesces** `mousemove` input: a long OS-cursor trajectory may reach
  an Agent Window page as only the final point's event. The trajectory script
  makes motion natural on screen; it is not a guarantee against
  mouse-trajectory bot checks. For motion the page actually observes, hover 2-4
  controls along a plausible route with random pauses.
- OS cursor coordinates are physical screen pixels in virtual-screen space. On
  scaled or multi-monitor setups, verify one landing point first.
- Pixel clicks (`--image-x`/`--image-y`) are Canvas-only in `bsk`; HTML targets
  are clicked by ref/selector, which still dispatches native mouse events.
- `human-pointer.ps1` moves the user's real cursor, so the pointer is occupied
  for the duration of the path.
- Some hosts reject a `powershell -File ...` invocation from a POSIX shell and a
  literal `Add-Type` in a command string. Call the script through the host's
  PowerShell tool by absolute path instead.
- File uploads and CAPTCHA/login steps keep the upstream escape hatches
  (`upload`, request-human-help).

## License

MIT © 2026 htlu1975. Builds upon Tencent BrowserSkill's browser-skill
(MIT © Tencent); see `LICENSE` and `references/`.
