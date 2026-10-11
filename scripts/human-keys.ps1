<#
human-keys.ps1 - Type ASCII text into the Agent Window with human-like per-key
timing, using OS-level keystrokes.

Why not `bsk press` (measured on Windows, Chrome 155, bsk 0.3.2):

  - bsk press is correct for ASCII: real key / code / keyCode, keypress, and an
    insertText input event. Its --hold-ms is honoured too.
  - But each call costs a full daemon round trip, so consecutive keys land
    ~660 ms apart. That is far slower than a human and is itself a signature.
  - keybd_event from this script lands around 190-230 ms per key at the defaults,
    with log-normal jitter, burst pauses every 8-15 keys, and bigram speedups.
    `Start-Sleep` on Windows has ~15 ms granularity, so the real figure sits a
    little above the nominal hold + gap.

Requirements:
  - The Agent Window must be the foreground window. keystrokes go to the focused
    window, and bsk's overlay does not intercept the keyboard, so page focus
    still has to be set with `bsk click --selector '<css>'` before calling this.

CJK: this script DOES reach the real IME, because keybd_event goes through the OS
input queue rather than through CDP. Feed it the zhuyin readings and it types
Chinese with a genuine composition stream - keydown reports key="Process" /
keyCode 229, there are two keyups per key, and the page sees compositionstart /
compositionupdate / insertCompositionText with isComposing true. Verified by
typing `w961o3` (ㄊㄞˊ then ㄅㄟˇ) to get 台北, on Windows with Microsoft Bopomofo
active. The tone mark auto-commits, so no Space is needed.

Two consequences to handle:
  - The IME mode is sticky per window. After a CJK run the next ASCII run is
    silently converted to zhuyin - this script still reports success
    ("typos=0"), so verify the field, not the log. Navigation keys are eaten too
    (a real OS PageDown fired no keydown until a Shift was tapped). Send one
    OS-level Shift to switch back; -ImeReset does it at the end of a run.
  - `bsk press` can do neither job: CDP input bypasses the IME completely. With
    the IME in Chinese mode, `bsk press a` inserts a literal "a".
Paste stays the simpler default for arbitrary CJK - a paste produces a genuine
`insertFromPaste` and needs no per-character readings.

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
  [double]$TransposeRate = 0.005, # chance of swapping two adjacent chars then fixing
  [int]$BurstMin = 8,             # burst-pause: think pause every N chars
  [int]$BurstMax = 15,
  [int]$StartDelayMs = 400,
  [int]$Seed = 0,
  [switch]$ImeReset,      # tap an OS-level Shift at the end (unsticks a Chinese IME)
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
  # Human Shift leads the key by 10-40 ms and lingers 10-30 ms after release.
  if ($shift) { [K.U]::keybd_event([byte]$VK_SHIFT, $shiftScan, 0, [System.UIntPtr]::Zero); Start-Sleep -Milliseconds ($rnd.Next(10, 41)) }
  [K.U]::keybd_event([byte]$vk, $scan, 0, [System.UIntPtr]::Zero)
  Start-Sleep -Milliseconds $holdMs
  [K.U]::keybd_event([byte]$vk, $scan, 0x0002, [System.UIntPtr]::Zero)
  if ($shift) { Start-Sleep -Milliseconds ($rnd.Next(10, 31)); [K.U]::keybd_event([byte]$VK_SHIFT, $shiftScan, 0x0002, [System.UIntPtr]::Zero) }
}
# QWERTY adjacency (US layout, lowercase). Typo picks a physical neighbour of
# the intended key instead of a random vowel, so the error looks like a miss.
$adjacent = @{
  'q'=@('w','a','1'); 'w'=@('q','e','a','s','2'); 'e'=@('w','r','s','d','3')
  'r'=@('e','t','d','f','4'); 't'=@('r','y','f','g','5'); 'y'=@('t','u','g','h','6')
  'u'=@('y','i','h','j','7'); 'i'=@('u','o','j','k','8'); 'o'=@('i','p','k','l','9')
  'p'=@('o','l','0'); 'a'=@('q','w','s','z'); 's'=@('w','e','a','d','x','z')
  'd'=@('e','r','s','f','x','c'); 'f'=@('r','t','d','g','c','v'); 'g'=@('t','y','f','h','v','b')
  'h'=@('y','u','g','j','b','n'); 'j'=@('u','i','h','k','n','m'); 'k'=@('i','o','j','l','m')
  'l'=@('o','p','k',';'); 'z'=@('a','s','x'); 'x'=@('z','s','d','c'); 'c'=@('x','d','f','v')
  'v'=@('c','f','g','b'); 'b'=@('v','g','h','n'); 'n'=@('b','h','j','m'); 'm'=@('n','j','k',',')
  ','=@('m','k','.'); '.'=@(',','l','/'); '/'=@('.',';')
  ' '=@(' '); "`t"=@("`t"); "`n"=@("`n")
}
# Frequent English bigrams type ~30% faster; rare pairs ~25% slower.
# Space-adjacent keys pause longer (word boundary planning).
$frequentBigrams = @('th','he','in','er','an','re','on','at','en','nd','ti','es','or','te','of','ed','is','it','al','ar','st','to','nt','ng','se','ha','as','ou','io','le','ve','co','me','de','hi','ri','ro','ic','ne','ea','ra','ce','li','ch','ll','be','ma','si','om','ur')
function Get-GapMs([string]$prev, [string]$curr) {
  # Log-normal-ish: uniform base warped by Box-Muller gaussian so most gaps
  # cluster near the low end with a long tail, like human inter-key times.
  $u1 = [Math]::Max(1e-6, $rnd.NextDouble()); $u2 = $rnd.NextDouble()
  $z = [Math]::Sqrt(-2.0 * [Math]::Log($u1)) * [Math]::Cos(2.0 * [Math]::PI * $u2)  # ~N(0,1)
  $base = ($GapMsMin + $GapMsMax) / 2.0 + $z * (($GapMsMax - $GapMsMin) / 4.0)
  if ($base -lt $GapMsMin) { $base = $GapMsMin + $rnd.Next(0, 15) }
  if ($base -gt ($GapMsMax * 2.2)) { $base = $GapMsMax * 2.2 }
  $factor = 1.0
  if ($prev -ne $null -and $prev.Length -gt 0) {
    $bg = ($prev + $curr).ToLower()
    if ($frequentBigrams -contains $bg) { $factor = 0.7 }
    elseif ($prev -eq $curr) { $factor = 0.75 }   # double letters are fast
    elseif ($prev -eq ' ' -or $curr -eq ' ') { $factor = 1.35 }  # word boundaries
    elseif ($curr -match '[A-Z]' -and $prev -cmatch '[a-z]') { $factor = 1.2 }
  }
  return [int][Math]::Max($GapMsMin, $base * $factor)
}
function Pause-Gap([string]$prev, [string]$curr) { Start-Sleep -Milliseconds (Get-GapMs $prev $curr) }

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
$chars = $Text.ToCharArray()
$prevKey = ''
$sinceBurst = 0
$nextBurstAt = $rnd.Next($BurstMin, $BurstMax + 1)
$typos = 0; $transposes = 0; $bursts = 0
for ($idx = 0; $idx -lt $chars.Length; $idx++) {
  $ch = $chars[$idx]
  $key = [string]$ch
  if ($ch -eq "`n") { Send-Key 0x0D $false ($rnd.Next($HoldMsMin, $HoldMsMax + 1)); $typed++; Pause-Gap $prevKey $key; $prevKey = $key; continue }
  if ($ch -eq "`t") { Send-Key 0x09 $false ($rnd.Next($HoldMsMin, $HoldMsMax + 1)); $typed++; Pause-Gap $prevKey $key; $prevKey = $key; continue }
  if (-not $table.ContainsKey($key)) { $unsupported += $key; continue }

  $hold = $rnd.Next($HoldMsMin, $HoldMsMax + 1)

  # Transposition: type next two chars swapped, notice, delete both, retype.
  if ($TransposeRate -gt 0 -and $idx + 1 -lt $chars.Length -and $rnd.NextDouble() -lt $TransposeRate) {
    $nk = [string]$chars[$idx + 1]
    if ($table.ContainsKey($nk) -and $key -match '[A-Za-z]' -and $nk -match '[A-Za-z]') {
      $v2 = $table[$nk]; Send-Key $v2[0] $v2[1] ($rnd.Next($HoldMsMin, $HoldMsMax + 1)); Pause-Gap $prevKey $nk
      $v1 = $table[$key]; Send-Key $v1[0] $v1[1] ($rnd.Next($HoldMsMin, $HoldMsMax + 1))
      Start-Sleep -Milliseconds $rnd.Next(200, 520)
      Send-Key 0x08 $false ($rnd.Next($HoldMsMin, $HoldMsMax + 1))
      Start-Sleep -Milliseconds $rnd.Next(60, 150)
      Send-Key 0x08 $false ($rnd.Next($HoldMsMin, $HoldMsMax + 1))
      Start-Sleep -Milliseconds $rnd.Next(90, 220)
      Send-Key $v1[0] $v1[1] ($rnd.Next($HoldMsMin, $HoldMsMax + 1)); Pause-Gap $prevKey $key
      Send-Key $v2[0] $v2[1] ($rnd.Next($HoldMsMin, $HoldMsMax + 1))
      $typed += 2; $transposes++; $prevKey = $nk; $idx++
      Pause-Gap $key $nk
      continue
    }
  }

  # Human slip: hit a QWERTY neighbour of the intended key, notice it,
  # backspace, retype. The text that ends up in the field is still exact.
  if ($rnd.NextDouble() -lt $TypoRate) {
    $lower = $key.ToLower()
    if ($adjacent.ContainsKey($lower)) {
      $cands = $adjacent[$lower]
      $wrongLower = $cands[$rnd.Next($cands.Length)]
      # Preserve case of the intended key.
      $wrong = if ($key -cmatch '[A-Z]') { $wrongLower.ToUpper() } else { $wrongLower }
      if ($table.ContainsKey($wrong)) {
        $wv = $table[$wrong]
        Send-Key $wv[0] $wv[1] ($rnd.Next($HoldMsMin, $HoldMsMax + 1))
        Start-Sleep -Milliseconds $rnd.Next(180, 520)
        Send-Key 0x08 $false ($rnd.Next($HoldMsMin, $HoldMsMax + 1))   # Backspace
        Start-Sleep -Milliseconds $rnd.Next(90, 220)
        $hold = $rnd.Next($HoldMsMin, $HoldMsMax + 1)
        $typos++
      }
    }
  }

  $v = $table[$key]
  Send-Key $v[0] $v[1] $hold
  $typed++
  Pause-Gap $prevKey $key
  $prevKey = $key
  $sinceBurst++

  # Sentence boundary: longer planning pause after . ! ?
  if ($key -match '[.!?]') { Start-Sleep -Milliseconds $rnd.Next(400, 900); $sinceBurst = 0; $nextBurstAt = $rnd.Next($BurstMin, $BurstMax + 1) }
  elseif ($sinceBurst -ge $nextBurstAt) {
    Start-Sleep -Milliseconds $rnd.Next(300, 800)  # burst-pause: chunk typing
    $bursts++; $sinceBurst = 0; $nextBurstAt = $rnd.Next($BurstMin, $BurstMax + 1)
  }
}

$ms = [int]([DateTime]::UtcNow - $t0).TotalMilliseconds
Write-Output "typed $typed char(s) in ${ms}ms (~$([Math]::Round($ms / [Math]::Max(1,$typed),0))ms/char) typos=$typos transposes=$transposes bursts=$bursts seed=$Seed"
if ($ImeReset) {
  # The IME mode is sticky: after Chinese, ASCII keeps transliterating until an
  # OS-level Shift switches it back. bsk press Shift is rejected, so do it here
  # while the foreground guarantee still holds.
  Send-Key $VK_SHIFT $false ($rnd.Next($HoldMsMin, $HoldMsMax + 1))
  Write-Output 'ime-reset: tapped OS Shift'
}
if ($unsupported.Count -gt 0) {
  $uniq = ($unsupported | Select-Object -Unique) -join ''
  Write-Output "SKIPPED $($unsupported.Count) char(s) not in the US table: '$uniq' (CJK goes through the OS IME - feed the zhuyin readings like 'w961o3', not the characters; otherwise paste)"
}
