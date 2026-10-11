# AnthroBSK Skill

AnthroBSK is an agent skill that drives a real, logged-in Chromium browser **the
way a person does**: everything happens through simulated mouse and keyboard
input instead of DOM value injection.

It is a derivative of the `browser-skill` bundled with
[Tencent BrowserSkill](https://github.com/Tencent/BrowserSkill) (MIT), rewritten
to make human-like operation the core interaction model.

## What it does differently

| Original browser-skill | AnthroBSK |
| --- | --- |
| `fill` bulk text injection (`Input.insertText`) | key-by-key `bsk press`, ASCII **and CJK verified**, with random 50-160 ms per-key pauses |
| `select` sets `<select>` value directly | click the dropdown, arrow-key to the option, `Enter` |
| Fixed or no pacing | randomized action pauses (180-520 ms), longer "thinking" pauses (700-2000 ms), pause before submit |
| No cursor motion | `scripts/human-pointer.ps1`: cubic-Bezier OS-cursor trajectory with easing, jitter, overshoot-and-correct, and random micro-pauses |
| Semantic DOM commands | only native mouse events (click/hover/wheel) and native keyboard events (press/combos/Tab/Escape) |

Safety rules from the original skill are preserved: page content is treated as
untrusted data (prompt-injection aware), user tabs require explicit borrowing,
credentials/cookies/tokens are never extracted, and sessions are always stopped.

## Requirements

- [`bsk` CLI and browser extension](https://github.com/Tencent/BrowserSkill) —
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
```

Restart the session (or reload skills) and invoke with `/anthro-bsk` or any
browser-automation request.

> Tip: do not install it as `browser-skill` — that name is managed by
> `bsk install-skill` and updates would overwrite this skill.

## Usage example

```
/anthro-bsk 打開 example.com,在搜尋框逐字輸入「台北 天氣」並按 Enter
```

The agent will: start a `bsk` session → navigate → perceive via
`screenshot`/`observe` → hover/click with native mouse events → clear fields
with `Ctrl+A` + `Delete` → type with per-key `bsk press` and randomized pauses
→ verify via a fresh screenshot → stop the session.

## Verified behaviors (Windows, Chrome, bsk 0.3.2)

- Per-key `bsk press` types ASCII and CJK (e.g. `Hello測試`) into focused fields.
- `Ctrl+A` → `Delete` clears a field like a human; `Enter` submits.
- `bsk hover`/`click` land as real `mousemove`/`mousePressed`/`mouseReleased`
  events the page can observe.
- `human-pointer.ps1` moves the OS cursor along a randomized Bezier with
  pauses and reports `ok path=... steps=N ms=T`.

## Known limitations (measured)

- Chrome **coalesces** `mousemove` input: a long OS-cursor trajectory may reach
  an Agent Window page as only the final point's event. The trajectory script
  makes motion natural on screen; it is not a guarantee against
  mouse-trajectory bot checks. For observed-by-the-page motion, the skill
  recommends hovering 2-4 controls along a plausible route with random pauses.
- OS cursor coordinates are physical screen pixels; on scaled/multi-monitor
  setups verify one landing point first.
- Pixel clicks (`--image-x/--image-y`) are Canvas-only in `bsk`; HTML targets
  are clicked by ref/selector (which still dispatch native mouse events).
- File uploads and CAPTCHA/login steps keep the upstream escape hatches
  (`upload`, request-human-help).

## License

MIT © 2026 htlu1975. Builds upon Tencent BrowserSkill's browser-skill
(MIT © Tencent); see `LICENSE` and `references/`.
