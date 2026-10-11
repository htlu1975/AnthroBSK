# Live verification (needs Windows + Chrome + bsk 0.3.2)

Offline first: `powershell -File tests/verify-offline.ps1`.

Live, with a `bsk` session `<id>`:

1. Serve the probe: `python -m http.server 8099 --directory tests`,
   then `bsk navigate http://localhost:8099/event-probe.html --session <id>`.
2. Hide bsk's overlay - needed for any OS press or drag:
   `bsk evaluate --session <id> 'document.querySelector("browser-skill-overlay").setAttribute("data-bsk-capture-hidden","")'`.
   Re-apply it after every `bsk screenshot` (only `screenshot` restores the
   overlay; `click`/`press`/`hover`/`observe` leave it hidden).
3. Pointer: focus the Agent Window, then run
   `human-pointer.ps1 -WindowTitleLike <title> -ViewportWidth <w> -ViewportHeight <h>`
   `-EndCssX <pad-x> -EndCssY <pad-y>`. Dump the probe (`dump JSON` button or
   `bsk evaluate "JSON.stringify(__probe.summary())"`). Expect 43-52
   `mousemove` over 1.2-3.1 s, deltas 0-67 px (the largest land mid-path where
   the pointer is fastest, not at the ends), 0 untrusted.
4. Click: `human-pointer.ps1 ... -Click`. Expect a hold of 66-132 ms
   (45-130 ms nominal, plus `Start-Sleep` granularity), `pointerdown.pressure`
   0.5, 43-52 `pointermove` while the button is down, and the target's own
   handler firing once. Without step 2 the press is swallowed and the field
   never focuses.
5. Keys (ASCII): `bsk click` the field to focus, then
   `human-keys.ps1 -WindowTitleLike <title> -Text "the quick brown fox" -Seed 7`.
   Expect the field to hold the exact text, `keydown`/`keyup` counts matching,
   `keypress` lower by the Backspace count when a typo fired.
6. Keys (CJK, real IME): with Microsoft Bopomofo active, run
   `human-keys.ps1 -WindowTitleLike <title> -Text "w961o3"`. Expect `?啣?`, six
   `compositionupdate` events, `isComposing: true`, and exactly one untrusted
   `compositionend` on blur. Press an **OS-level** Shift afterwards before
   typing ASCII again - the IME mode is sticky, and `bsk press Shift` is rejected.
7. Wheel (RESOLVED - keep as a regression check): Windows sends the wheel to the
   window UNDER THE CURSOR, not the foreground window, which is why the first
   "no-op" verdict was wrong. With the cursor parked and the overlay hidden:
   a. Hide the overlay (step 2), then park the cursor over the probe's wheel
      box: `human-wheel.ps1 -WindowTitleLike <title> -DeltaY 600
      -ViewportWidth <w> -ViewportHeight <h> -CssX <box-x> -CssY <box-y>`.
   b. Expected: 4 `isTrusted` `wheel` events with the right target and decaying
      deltaY, and `defaultPrevented: true` on each - so `scrollTop` stays 0. That
      is the correct, measured result, not a failure.
   c. The block is the extension: the probe page defines no `wheel` handler that
      calls `preventDefault`/`stopPropagation`, yet the events arrive already
      `defaultPrevented` and never reach `document`. It is `preventDefault`ing
      real wheel in its isolated world at `window` capture. Tested with the
      overlay both hidden and visible - identical, so the overlay element is not
      the cause.
   d. Control that the OS path itself is live: `bsk wheel --delta-y 600` scrolls
      the box (`scrollTop` 496) with `defaultPrevented: false` - the extension
      exempts its own CDP event. To scroll, use `bsk wheel`; to get real `wheel`
      events in the page, use `human-wheel.ps1`.
   e. Navigation keys are NOT blocked: with the IME off, an OS `PageDown` scrolled
      `scrollY` 93 -> 366 and fired a trusted `keydown`. If it appears dead, the
      Chinese IME is on and eating the key - tap an OS Shift first.
8. Paste: `printf '%s' '?啣?憭拇除' | clip.exe`, then `bsk press Ctrl+V`.
   Expect one `insertFromPaste` and value `ab?啣?憭拇除` when mixed with typed `ab`.
