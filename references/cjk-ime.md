# CJK through the real IME (Microsoft Bopomofo)

`bsk press` cannot drive an IME: in Chinese mode it inserts a literal ASCII
letter with no composition at all. OS-level keystrokes from
`scripts/human-keys.ps1` reach the installed IME and produce a genuine
composition stream (`keyCode 229`, `compositionstart`/`update`/`end`,
`inputType: insertCompositionText`, `isComposing: true`). Verified: typing
`w961o3` produced `台北`, tone mark committing each syllable, no space needed.

## Feed readings, not characters

The script sends US-layout virtual keys; the IME translates them. So the agent
must supply the **zhuyin reading keystrokes**, not the CJK characters:

| Syllable | Zhuyin | Keystrokes | Note |
| --- | --- | --- | --- |
| 台 | ㄊㄞˊ | `w` `9` `6` | consonant + vowel + tone commits |
| 北 | ㄅㄟˇ | `1` `o` `3` | `1` starts the next syllable |

## Key map (Daqian / 大千 layout, US keyboard)

Consonants: `1`ㄅ `q`ㄆ `a`ㄇ `z`ㄈ `2`ㄉ `w`ㄊ `s`ㄋ `x`ㄌ `e`ㄍ `d`ㄎ `c`ㄏ
`r`ㄐ `f`ㄑ `v`ㄒ `5`ㄓ `t`ㄔ `g`ㄕ `b`ㄖ `y`ㄗ `h`ㄘ `n`ㄙ

Vowels: `u`ㄧ `j`ㄨ `m`ㄩ `8`ㄚ `i`ㄛ `k`ㄜ `,`ㄝ `9`ㄞ `o`ㄟ `l`ㄠ `.`ㄡ `0`ㄢ
`p`ㄣ `-`ㄤ `/`ㄥ

Tones: `6`ˊ (2nd) `3`ˇ (3rd) `4`ˋ (4th) `7`˙ (neutral); 1st tone needs no mark.
The tone keystroke **commits** the syllable.

## Sticky mode and reset

After Chinese, the IME stays in Chinese mode and ASCII keeps transliterating.
Reset with an OS-level Shift: `human-keys.ps1 ... -ImeReset` taps it at the end
while the foreground guarantee holds. `bsk press Shift` is rejected - never use
it for this.

## Mixed ASCII + CJK recipe (one field, focus held throughout)

1. Focus once: `bsk click @ref` (overlay hidden first - see SKILL.md).
2. Type each ASCII run: `human-keys.ps1 -Text "<ascii>"`.
3. Type each CJK run as readings: `human-keys.ps1 -Text "<zhuyin>"`.
4. Finish the last run with `-ImeReset`, verify the field text, then submit.

Characters outside the IME's coverage (or an unknown reading): fall back to
clipboard paste (`insertFromPaste`), which is honest but leaves 0 keydowns -
see the forensics note in the README. Non-BMP characters (emoji, CJK Ext B+)
are rejected by `bsk press` with `press: unknown key` either way.
