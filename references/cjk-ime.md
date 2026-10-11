# CJK through the real IME (Microsoft Bopomofo)

`bsk press` cannot drive an IME: in Chinese mode it inserts a literal ASCII
letter with no composition at all. OS-level keystrokes from
`scripts/human-keys.ps1` reach the installed IME and produce a genuine
composition stream (`keyCode 229`, `compositionstart`/`update`/`end`,
`inputType: insertCompositionText`, `isComposing: true`). Verified: typing
`w961o3` produced `?啣?`, tone mark committing each syllable, no space needed.

## Feed readings, not characters

The script sends US-layout virtual keys; the IME translates them. So the agent
must supply the **zhuyin reading keystrokes**, not the CJK characters:

| Syllable | Zhuyin | Keystrokes | Note |
| --- | --- | --- | --- |
| ??| ??? | `w` `9` `6` | consonant + vowel + tone commits |
| ??| ??? | `1` `o` `3` | `1` starts the next syllable |

## Key map (Daqian / 憭批? layout, US keyboard)

Consonants: `1`??`q`??`a`??`z`??`2`??`w`??`s`??`x`??`e`??`d`??`c`??`r`??`f`??`v`??`5`??`t`??`g`??`b`??`y`??`h`??`n`??
Vowels: `u`??`j`??`m`??`8`??`i`??`k`??`,`??`9`??`o`??`l`??`.`??`0`??`p`??`-`??`/`??
Tones: `6`? (2nd) `3`? (3rd) `4`? (4th) `7`? (neutral); 1st tone needs no mark.
The tone keystroke **commits** the syllable.

## Sticky mode and reset

After Chinese, the IME stays in Chinese mode and ASCII keeps transliterating.
Reset with an OS-level Shift: `human-keys.ps1 ... -ImeReset` taps it at the end
while the foreground guarantee holds. `bsk press Shift` is rejected - never use
it for this.

This is not cosmetic. With the IME still on, a later ASCII run silently
mistypes - `human-keys.ps1 -Text "abc"` reports `typed 3 char(s) ... typos=0`
while the field receives `? and `?, and navigation keys are swallowed (a real
OS `PageDown` produced no `keydown` at all until an OS Shift was tapped, then it
scrolled normally). So before any ASCII or navigation-key run, confirm the IME
is off - tap an OS Shift if unsure. The script cannot detect this, because it
never reads the field back.

## Mixed ASCII + CJK recipe (one field, focus held throughout)

1. Focus once: `bsk click @ref` (overlay hidden first - see SKILL.md).
2. Type each ASCII run: `human-keys.ps1 -Text "<ascii>"`.
3. Type each CJK run as readings: `human-keys.ps1 -Text "<zhuyin>"`.
4. Finish the last run with `-ImeReset`, verify the field text, then submit.

Characters outside the IME's coverage (or an unknown reading): fall back to
clipboard paste (`insertFromPaste`), which is honest but leaves 0 keydowns -
see the forensics note in the README. Non-BMP characters (emoji, CJK Ext B+)
are rejected by `bsk press` with `press: unknown key` either way.
