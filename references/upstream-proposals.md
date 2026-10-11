# Upstream proposals for `bsk` (Tencent BrowserSkill)

These are skill-side workarounds today; each needs a CLI/extension change to
fix properly. Measurements from README/SKILL (Windows, Chrome 155, bsk 0.3.2).

## 1. Overlay input-blocking + fingerprint

- **Today:** `browser-skill-overlay` is a direct child of `<html>` with
  `position: fixed`, `z-index: 2147483647`, a shadow root, and
  `data-bsk-overlay` / `data-bsk-overlay-surface` / `data-bsk-overlay-blocking`.
  `elementFromPoint` returns `BROWSER-SKILL-OVERLAY`, so OS clicks are swallowed
  end to end (cursor moves, 95 ms hold, focus never moves).
- **The extension already has a switch.** Its shadow root ships
  `:host([data-bsk-capture-hidden]) { display: none !important; }` and
  `:host([data-bsk-overlay-surface][data-bsk-overlay-blocking]) { pointer-events:
  auto !important; }`. Setting `data-bsk-capture-hidden` makes the overlay
  `display: none`, hit-testing falls through, and OS-level input works. That is
  the current workaround - but it is an undocumented internal attribute, it is
  cleared again by `screenshot`, and it hides the user's own indicator.
- **Ask:** promote the existing attribute to a documented contract - e.g.
  `bsk overlay --mode hidden|visible` plus a `--keep-hidden` session option that
  survives `screenshot` - and document the `data-bsk-*` attribute set so pages
  that must not see automation know what to expect. Also make the `pointer-events`
  state reachable without hiding the overlay entirely, so an agent can take OS
  input without removing the user's on-page signal.
- **Do not** try to remove the element: it is re-injected, and a removal loop
  livelocks the renderer (observed: the tab had to be closed).

## 2. Click timing options

- **Today:** one `bsk click` = 1 `mousemove`, `mousedown` 2-4 ms later, `mouseup`
  0.8-2 ms after; ~6 ms total, `pressure: 0` while down. `click` has no
  hold/pre-move option.
- **Workaround:** hide the overlay, then `human-pointer.ps1 -Click` gives a real
  OS gesture - 43-52 `mousemove` over 1.2-3.1 s, 80-250 ms dwell, 66-132 ms hold,
  `pressure: 0.5` while down, 0 untrusted events. Verified against a `<button>`
  whose handler fired.
- **Ask:** `bsk click --hold-ms <n> --move-ms <n> [--dwell-ms <n>]` dispatched
  through the same native path, so hover ??dwell ??press ??hold ??release is one
  gesture instead of teleport + 6 ms tap. This is the last piece that still needs
  the skill to shell out to Windows-only code.

## 3. Batched key rhythm

- **Today:** each `bsk press` costs a daemon round trip (~660 ms/key, ~0.9-1.2 s
  process cost), so per-key `wait-ms` cannot produce human rhythm. The skill
  shells out to `human-keys.ps1` for ASCII.
- **CJK is solved, but not by CDP.** OS-level keystrokes reach the installed IME
  and produce a genuine composition stream (`keyCode 229`, two keyups per key,
  `insertCompositionText`, `isComposing: true`). CDP input bypasses the IME
  entirely: with the IME in Chinese mode, `bsk press a` inserts a literal `a`.
- **Ask:** `bsk type --text <s> --min-gap --max-gap [--typo-rate]` (or batch
  `press`) that emits one CDP session's key sequence with jittered gaps and real
  hold durations. For CJK, either expose a real IME path or state explicitly that
  CDP cannot drive an IME, so skills stop assuming `press` covers it.

## 4. Multi-tick wheel, and wheel events that reach the page

- **Today:** `wheel --delta-y 600` is one discrete jump; humans send 3-6 decaying
  ticks. Each call costs ~1 s, so scripting decay via repeated calls is slow.
- **The real mechanism (measured - corrects an earlier wrong note).**
  `mouse_event(MOUSEEVENTF_WHEEL)` does work; the earlier "no-op" verdict was a
  cursor-positioning artefact. Windows sends the wheel to the window *under the
  cursor*, not the foreground window, and the cursor was parked over another app.
  With the cursor parked over a scrollable box and the overlay hidden, the page
  receives 4 `wheel` events - `isTrusted: true`, correct target, deltaY decaying
  236 -> 166 -> 117 -> 82 - but each arrives `defaultPrevented: true` and the box
  does not scroll. The probe page defines no `wheel` handler, so the extension is
  `preventDefault`ing real wheel in its isolated world at `window` capture; it
  also `stopPropagation`s, so `document` capture and the target listener never
  fire (the main world's `Event.prototype.preventDefault` never sees the call).
  It exempts its own CDP event: `bsk wheel` scrolls (`scrollTop` 496,
  `defaultPrevented: false`). Keyboard navigation is unaffected - a real OS
  `PageDown` scrolled the page and fired a trusted `keydown` (an earlier
  "PageDown does nothing" note was the Chinese IME eating the key, not this).
- **Ask:** (a) `bsk wheel --delta-y <n> --ticks <k> --decay <f>` emitting a
  decayed burst natively. (b) Stop swallowing real `wheel` at `window` capture -
  or state explicitly that page-visible `wheel` events are intentionally
  withheld. Today the split is: `bsk wheel` scrolls but the page cannot observe
  it; `human-wheel.ps1` produces real, page-visible `wheel` events the page
  cannot act on. Either way, say which one the caller gets.

## 5. Readiness primitive

- **Today:** no `wait-for-element` in 0.3.2; only `wait-ms` + `wait-for-navigation`.
- **Ask:** restore a selector/ref wait (or document the replacement), so skills
  stop polling with `observe` loops.

When filing upstream, link the measured runs in README ("What this is NOT")
and SKILL ("Verified limitation" notes) rather than re-arguing stealth:
`isTrusted: true` holds on both channels; timing and event shape are what differ.
