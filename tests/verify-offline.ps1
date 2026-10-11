<#
verify-offline.ps1 - Offline checks for AnthroBSK scripts. No Chrome, no bsk needed.
Run: powershell -File tests/verify-offline.ps1  (or pwsh)
Checks:
  1. All scripts/*.ps1 parse with zero syntax errors.
  2. Required params / switches still exist (contract the SKILL.md documents).
  3. human-wheel.ps1 sign convention: -DeltaY>0 must emit negative wheel data.
  4. human-keys.ps1 adjacency map covers a-z; frequent-bigram list non-empty.
  5. human-pointer.ps1 defines MinJerk and OU tremor state.
Exit non-zero on first failure, printing FAIL lines.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$scripts = Get-ChildItem (Join-Path $root 'scripts') -Filter '*.ps1'
$fail = 0
function Ok($msg) { Write-Output "PASS: $msg" }
function Bad($msg) { Write-Output "FAIL: $msg"; $script:fail++ }

foreach ($f in $scripts) {
  $tokens = $null; $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
  if ($errors.Count -eq 0) { Ok "$($f.Name) parses clean" } else { Bad "$($f.Name) has $($errors.Count) syntax error(s): $($errors[0].Message)" }
}

# --- contract checks against file text (cheap, version-proof) ---
$keys = Get-Content (Join-Path $root 'scripts/human-keys.ps1') -Raw
foreach ($need in @('TransposeRate', 'BurstMin', 'adjacent', 'frequentBigrams', 'Get-GapMs', 'Min', 'Max')) {
  if ($keys -match [regex]::Escape($need)) { Ok "human-keys.ps1 contains '$need'" } else { Bad "human-keys.ps1 missing '$need'" }
}
foreach ($ch in [char[]]'abcdefghijklmnopqrstuvwxyz') {
  if ($keys -notmatch "'$ch'") { Bad "human-keys.ps1 adjacency missing key '$ch'"; break }
}
Ok 'human-keys.ps1 adjacency covers a-z'

$ptr = Get-Content (Join-Path $root 'scripts/human-pointer.ps1') -Raw
foreach ($need in @('MinJerk', 'TremorPx', '$Drag', 'DwellMsMin', 'trx', 'try')) {
  if ($ptr -match [regex]::Escape($need)) { Ok "human-pointer.ps1 contains '$need'" } else { Bad "human-pointer.ps1 missing '$need'" }
}
if ($ptr -match '\$sy = B 0\.75 \$startPX') { Bad 'human-pointer.ps1 still has the X/Y copy slip in $sy' }
else { Ok 'human-pointer.ps1 correction leg uses the Y curve' }

$wheel = Get-Content (Join-Path $root 'scripts/human-wheel.ps1') -Raw
foreach ($need in @('0x0800', '0x1000', 'Ticks', 'decay')) {
  if ($wheel -match [regex]::Escape($need)) { Ok "human-wheel.ps1 contains '$need'" } else { Bad "human-wheel.ps1 missing '$need'" }
}
# The wheel goes to the window under the cursor, not the foreground window, so
# the script must be able to park the cursor over the scroll target first.
foreach ($need in @('$CssX', 'FindWidget', 'Move-Physical', 'parked')) {
  if ($wheel -match [regex]::Escape($need)) { Ok "human-wheel.ps1 contains '$need'" } else { Bad "human-wheel.ps1 missing '$need' (cursor parking)" }
}
if ($wheel -match '\-\$wy') { Ok 'human-wheel.ps1 negates Y (screen-Y-down to wheel sign)' }
else { Bad 'human-wheel.ps1 Y-sign convention missing (-$wy)' }
# Regression guard: mouse_event's dwData must not be cast to [uint32]. PowerShell
# refuses to convert a negative value at runtime ("Value was either too large or
# too small"), so every tick threw while the script still printed a success line
# and exited 0 - zero wheel events, and offline checks could not see it.
if ($wheel -match '\[uint32\]\s*\(') { Bad 'human-wheel.ps1 casts to [uint32] - negative dwData will throw at runtime' }
else { Ok 'human-wheel.ps1 does not cast dwData to [uint32]' }
if ($wheel -match "ErrorActionPreference\s*=\s*'Stop'") { Ok 'human-wheel.ps1 fails loudly on a P/Invoke error' }
else { Bad "human-wheel.ps1 lacks `$ErrorActionPreference = 'Stop'" }

$probe = Join-Path $root 'tests/event-probe.html'
if (Test-Path $probe) { Ok 'tests/event-probe.html exists' } else { Bad 'tests/event-probe.html missing' }
$probeText = Get-Content $probe -Raw
foreach ($need in @('compositionstart', 'compositionupdate', 'compositionend', 'wheelWinCapture')) {
  if ($probeText -match [regex]::Escape($need)) { Ok "event-probe.html records '$need'" } else { Bad "event-probe.html missing '$need'" }
}

# The overlay contract is what makes OS-level input possible at all; losing it
# from SKILL.md would silently break the documented recipe.
$skill = Get-Content (Join-Path $root 'SKILL.md') -Raw
foreach ($need in @('data-bsk-capture-hidden', 'data-bsk-overlay-blocking', 'insertCompositionText', 'human-wheel.ps1')) {
  if ($skill -match [regex]::Escape($need)) { Ok "SKILL.md documents '$need'" } else { Bad "SKILL.md missing '$need'" }
}

# human-keys.ps1 used to claim CJK was impossible through the IME. That was
# disproved; make sure the stale claim does not come back.
$keysRaw = Get-Content (Join-Path $root 'scripts/human-keys.ps1') -Raw
if ($keysRaw -match 'CJK is deliberately not supported') { Bad 'human-keys.ps1 still says CJK is unsupported' }
else { Ok 'human-keys.ps1 no longer claims CJK is unsupported' }
if ($keysRaw -match 'compositionstart') { Ok 'human-keys.ps1 documents the IME composition stream' }
else { Bad 'human-keys.ps1 does not document the IME composition stream' }

if ($fail -gt 0) { Write-Output "$fail check(s) FAILED"; exit 1 }
Write-Output 'All offline checks passed.'
