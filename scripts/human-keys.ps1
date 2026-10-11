<#
human-keys.ps1 - Type ASCII text into the Agent Window with human-like per-key
timing, using OS-level keystrokes.

Why not `bsk press` (measured on Windows, Chrome 155, bsk 0.3.2):

  - bsk press is correct for ASCII: real key / code / keyCode, keypress, and an
    insertText input event. Its --hold-ms is honoured too.
  - But each call costs a full daemon round trip, so consecutive keys land
    ~660 ms apart. That is far slower than a human and is itself a signature.
  - keybd_event from this script lands around 190 ms per key at the defaults,
    with per-key jitter. `Start-Sleep` on Windows has ~15 ms granularity, so the
    real figure sits a little above the nominal hold + gap.

Requirements:
  - The Agent Window must be the foreground window. keystrokes go to the focused
    window, and bsk's overlay does not intercept the keyboard, so page focus
    still has to be set with `bsk focus @ref` before calling this.

CJK is deliberately not supported here. Typing Chinese through the real IME
means driving candidate selection, and the layout handle resolves to 0x0 in this
context, so character translation is unreliable. Paste instead - a clipboard
paste produces a genuine `insertFromPaste` input event, which is exactly what a
human paste produces.

Usage:
  & human-keys.ps1 -WindowTitleLike "My Page - Google Chrome" -Text "hello world"
  & human-keys.ps1 -ListWindows
  # optional: -HoldMsMin -HoldMsMax -GapMsMin -GapMsMax -TypoRate -Seed
#>
param(
  [string]$WindowTitleLike = "",
  [string]$Text = "",
  [int]$HoldMsMin = 30,
  [int]$HoldMsMax = 90,
  [int]$GapMsMin = 45,
  [int]$GapMsMax = 190,
  [double]$TypoRate = 0.03,      # chance of a wrong key followed by a correction
  [int]$StartDelayMs = 400,
  [int]$Seed = 0,
  [switch]$ListWindows
)

Add-Type -Namespace K -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, System.UIntPtr extra);
[DllImport("user32.dll")] public static extern uint MapVirtualKeyW(uint code, uint mapType);
[DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr h);
[DllImport("user32.dll")] public static extern bool BringWindowToTop(System.IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int cmd);
[DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, System.IntPtr l);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr h);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextW(System.IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassNameW(System.IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
[DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
public delegate bool EP(System.IntPtr h, System.IntPtr l);
public static string Want = "";
public static System.IntPtr Found = System.IntPtr.Zero;
public static bool Cb(System.IntPtr h, System.IntPtr l) {
  if (!IsWindowVisible(h)) return true;
  var c = new System.Text.StringBuilder(256); GetClassNameW(h, c, 256);
  var t = new System.Text.StringBuilder(512); GetWindowTextW(h, t, 512);
  if (c.ToString() == "Chrome_WidgetWin_1" && t.ToString().Contains(Want)) { Found = h; return false; }
  return true;
}
public static System.IntPtr FindTop(string want) {
  Found = System.IntPtr.Zero; Want = want;
  EnumWindows(new EP(Cb), System.IntPtr.Zero);
  return Found;
}
public static string TitleOf(System.IntPtr h) {
  var t = new System.Text.StringBuilder(512); GetWindowTextW(h, t, 512); return t.ToString();
}
'@

[void][K.U]::SetProcessDPIAware()
$rnd = if ($Seed -ne 0) { [System.Random]::new($Seed) } else { [System.Random]::new() }

# US-layout character table: character -> @(virtualKey, needsShift).
# Non-US layouts would need their own table; the keystroke itself is layout
# independent, but which key produces which character is not.
#
# This must be an ordinal dictionary. A plain @{} literal in PowerShell is
# case-insensitive, so 'a' and 'A' would collapse onto a single key and the
# uppercase pass would silently apply Shift to every letter.
$VK_SHIFT = 0x10
$table = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
$pairs = @(
  @(' ', 0x20, $false), @('`', 0xC0, $false), @('~', 0xC0, $true),
  @('-', 0xBD, $false), @('_', 0xBD, $true), @('=', 0xBB, $false), @('+', 0xBB, $true),
  @('[', 0xDB, $false), @('{', 0xDB, $true), @(']', 0xDD, $false), @('}', 0xDD, $true),
  @('\', 0xDC, $false), @('|', 0xDC, $true), @(';', 0xBA, $false), @(':', 0xBA, $true),
  @("'", 0xDE, $false), @('"', 0xDE, $true), @(',', 0xBC, $false), @('<', 0xBC, $true),
  @('.', 0xBE, $false), @('>', 0xBE, $true), @('/', 0xBF, $false), @('?', 0xBF, $true),
  @('!', 0x31, $true), @('@', 0x32, $true), @('#', 0x33, $true), @('$', 0x34, $true),
  @('%', 0x35, $true), @('^', 0x36, $true), @('&', 0x37, $true), @('*', 0x38, $true),
  @('(', 0x39, $true), @(')', 0x30, $true)
)
foreach ($p in $pairs) { $table[$p[0]] = @($p[1], $p[2]) }
foreach ($d in 0..9) { $table["$d"] = @((0x30 + $d), $false) }
foreach ($c in [char[]]'abcdefghijklmnopqrstuvwxyz') { $table["$c"] = @([int][char]([string]$c).ToUpper()[0], $false) }
foreach ($c in [char[]]'ABCDEFGHIJKLMNOPQRSTUVWXYZ') { $table["$c"] = @([int][char]$c, $true) }

function Set-ForegroundVerified([System.IntPtr]$top, [int]$Attempts = 3) {
  for ($i = 1; $i -le $Attempts; $i++) {
    if ([K.U]::GetForegroundWindow() -eq $top) { return $true }
    $fgPid = 0
    $fgTid = [K.U]::GetWindowThreadProcessId([K.U]::GetForegroundWindow(), [ref]$fgPid)
    $myTid = [K.U]::GetCurrentThreadId()
    [void][K.U]::AttachThreadInput($myTid, $fgTid, $true)
    [void][K.U]::ShowWindow($top, 9)
    [void][K.U]::BringWindowToTop($top)
    [void][K.U]::SetForegroundWindow($top)
    [void][K.U]::AttachThreadInput($myTid, $fgTid, $false)
    Start-Sleep -Milliseconds 250
    if ([K.U]::GetForegroundWindow() -eq $top) { return $true }
  }
  return $false
}

function Send-Key([int]$vk, [bool]$shift, [int]$holdMs) {
  $scan = [byte][K.U]::MapVirtualKeyW([uint32]$vk, 0)
  $shiftScan = [byte][K.U]::MapVirtualKeyW([uint32]$VK_SHIFT, 0)
  if ($shift) { [K.U]::keybd_event([byte]$VK_SHIFT, $shiftScan, 0, [System.UIntPtr]::Zero) }
  [K.U]::keybd_event([byte]$vk, $scan, 0, [System.UIntPtr]::Zero)
  Start-Sleep -Milliseconds $holdMs
  [K.U]::keybd_event([byte]$vk, $scan, 0x0002, [System.UIntPtr]::Zero)
  if ($shift) { [K.U]::keybd_event([byte]$VK_SHIFT, $shiftScan, 0x0002, [System.UIntPtr]::Zero) }
}
function Pause-Gap { Start-Sleep -Milliseconds ($rnd.Next($GapMsMin, $GapMsMax + 1)) }

if ($ListWindows) {
  Write-Output "foreground: '$([K.U]::TitleOf([K.U]::GetForegroundWindow()))'"
  Write-Output ""
  [K.U]::Found = [System.IntPtr]::Zero; [K.U]::Want = ""
  [void][K.U]::EnumWindows([K.U+EP] { param($h, $l) [K.U]::Cb($h, $l) }, [System.IntPtr]::Zero)
  # Cb stops at the first hit, so enumerate again without the early return.
  $found = @()
  [void][K.U]::EnumWindows([K.U+EP] {
    param($h, $l)
    if ([K.U]::IsWindowVisible($h)) {
      $c = [System.Text.StringBuilder]::new(256); [void][K.U]::GetClassNameW($h, $c, 256)
      if ($c.ToString() -eq 'Chrome_WidgetWin_1') { $script:found += $h }
    }
    return $true
  }, [System.IntPtr]::Zero)
  foreach ($h in $found) { Write-Output "hwnd=$h '$([K.U]::TitleOf($h))'" }
  exit 0
}

if ([string]::IsNullOrWhiteSpace($WindowTitleLike)) { Write-Output "ERROR: -WindowTitleLike is required (-ListWindows lists candidates)"; exit 2 }
if ($Text.Length -eq 0) { Write-Output "ERROR: -Text is empty"; exit 2 }

$top = [K.U]::FindTop($WindowTitleLike)
if ($top -eq [System.IntPtr]::Zero) { Write-Output "ERROR: no visible Chrome window whose title contains '$WindowTitleLike'"; exit 3 }

if (-not (Set-ForegroundVerified $top)) {
  Write-Output "ERROR: could not bring the Agent Window to the foreground. Keystrokes would go to the wrong window. Nothing was typed."
  exit 5
}
Start-Sleep -Milliseconds $StartDelayMs

$unsupported = @()
$t0 = [DateTime]::UtcNow
$typed = 0
foreach ($ch in $Text.ToCharArray()) {
  $key = [string]$ch
  if ($ch -eq "`n") { Send-Key 0x0D $false ($rnd.Next($HoldMsMin, $HoldMsMax + 1)); $typed++; Pause-Gap; continue }
  if ($ch -eq "`t") { Send-Key 0x09 $false ($rnd.Next($HoldMsMin, $HoldMsMax + 1)); $typed++; Pause-Gap; continue }
  if (-not $table.ContainsKey($key)) { $unsupported += $key; continue }

  $hold = $rnd.Next($HoldMsMin, $HoldMsMax + 1)

  # Human slip: hit a neighbouring key, notice it, backspace, retype. The text
  # that ends up in the field is still exactly what was asked for.
  if ($rnd.NextDouble() -lt $TypoRate) {
    $neighbours = @('a','e','i','o','u','s','t','n','r','l')
    $wrong = $neighbours[$rnd.Next($neighbours.Length)]
    $wv = $table[$wrong]
    Send-Key $wv[0] $wv[1] ($rnd.Next($HoldMsMin, $HoldMsMax + 1))
    Start-Sleep -Milliseconds $rnd.Next(180, 520)
    Send-Key 0x08 $false ($rnd.Next($HoldMsMin, $HoldMsMax + 1))   # Backspace
    Start-Sleep -Milliseconds $rnd.Next(90, 220)
    $hold = $rnd.Next($HoldMsMin, $HoldMsMax + 1)
  }

  $v = $table[$key]
  Send-Key $v[0] $v[1] $hold
  $typed++
  Pause-Gap
}

$ms = [int]([DateTime]::UtcNow - $t0).TotalMilliseconds
Write-Output "typed $typed char(s) in ${ms}ms (~$([Math]::Round($ms / [Math]::Max(1,$typed),0))ms/char)"
if ($unsupported.Count -gt 0) {
  $uniq = ($unsupported | Select-Object -Unique) -join ''
  Write-Output "SKIPPED $($unsupported.Count) char(s) not in the US table: '$uniq' (CJK and other non-ASCII: use clipboard paste instead)"
}
