<#
human-wheel.ps1 - Scroll the Agent Window with a human-like wheel gesture.

Why: one `bsk wheel --delta-y 600` arrives as a single discrete jump. A human
wheel arrives as 3-6 small ticks that decay (fast flick, then settle), with
40-140 ms between ticks and occasional longer coasting pauses.

This script drives the OS wheel via mouse_event(MOUSEEVENTF_WHEEL), so the page
sees real wheel events with isTrusted:true while the Agent Window is in the
foreground. Same focus contract as human-pointer/human-keys: it forces the
Agent Window to the foreground and exits non-zero if it cannot.

Usage:
  & human-wheel.ps1 -WindowTitleLike "My Page - Google Chrome" -DeltaY 600
  & human-wheel.ps1 -WindowTitleLike "..." -DeltaY -400 -Ticks 5
  & human-wheel.ps1 -ListWindows

  -DeltaY > 0 scrolls down, < 0 scrolls up (CSS px intent, converted to ticks).
  -Ticks 0 = auto (3-6 by distance). -Seed for reproducibility.
#>
param(
  [string]$WindowTitleLike = "",
  [int]$DeltaY = 400,
  [int]$DeltaX = 0,
  [int]$Ticks = 0,
  [int]$Seed = 0,
  [switch]$ListWindows
)

# A P/Invoke argument failure is a hard error, not something to shrug past:
# without this, a throwing mouse_event call still let the script print a
# success line and exit 0 while nothing had scrolled.
$ErrorActionPreference = 'Stop'

Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, int d, System.UIntPtr e);
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

[void][W.U]::SetProcessDPIAware()
$rnd = if ($Seed -ne 0) { [System.Random]::new($Seed) } else { [System.Random]::new() }

function Set-ForegroundVerified([System.IntPtr]$top, [int]$Attempts = 3) {
  for ($i = 1; $i -le $Attempts; $i++) {
    if ([W.U]::GetForegroundWindow() -eq $top) { return $true }
    $fgPid = 0
    $fgTid = [W.U]::GetWindowThreadProcessId([W.U]::GetForegroundWindow(), [ref]$fgPid)
    $myTid = [W.U]::GetCurrentThreadId()
    [void][W.U]::AttachThreadInput($myTid, $fgTid, $true)
    [void][W.U]::ShowWindow($top, 9)
    [void][W.U]::BringWindowToTop($top)
    [void][W.U]::SetForegroundWindow($top)
    [void][W.U]::AttachThreadInput($myTid, $fgTid, $false)
    Start-Sleep -Milliseconds 250
    if ([W.U]::GetForegroundWindow() -eq $top) { return $true }
  }
  return $false
}

if ($ListWindows) {
  Write-Output "foreground: '$([W.U]::TitleOf([W.U]::GetForegroundWindow()))'"
  exit 0
}

if ([string]::IsNullOrWhiteSpace($WindowTitleLike)) { Write-Output "ERROR: -WindowTitleLike is required"; exit 2 }
if ($DeltaY -eq 0 -and $DeltaX -eq 0) { Write-Output "ERROR: -DeltaY/-DeltaX are both 0, nothing to scroll"; exit 2 }

$top = [W.U]::FindTop($WindowTitleLike)
if ($top -eq [System.IntPtr]::Zero) { Write-Output "ERROR: no visible Chrome window whose title contains '$WindowTitleLike'"; exit 3 }
if (-not (Set-ForegroundVerified $top)) {
  Write-Output "ERROR: could not bring the Agent Window to the foreground. Nothing was scrolled."
  exit 5
}
Start-Sleep -Milliseconds $rnd.Next(150, 350)  # settle after focus

# Decide tick count: bigger intent = more ticks, 3-6 typical for a flick.
$total = [Math]::Abs($DeltaY) + [Math]::Abs($DeltaX)
if ($Ticks -le 0) {
  if ($total -lt 200) { $Ticks = $rnd.Next(2, 4) }
  elseif ($total -lt 600) { $Ticks = $rnd.Next(3, 6) }
  else { $Ticks = $rnd.Next(4, 7) }
}

# Decaying weights: first tick largest, tail coasts. Normalise to sum 1.
$weights = @()
$decay = 0.55 + $rnd.NextDouble() * 0.2  # 0.55-0.75 per tick
$w = 1.0
for ($i = 0; $i -lt $Ticks; $i++) { $weights += $w; $w *= $decay }
$sum = ($weights | Measure-Object -Sum).Sum

$t0 = [DateTime]::UtcNow
for ($i = 0; $i -lt $Ticks; $i++) {
  $frac = $weights[$i] / $sum
  # Convert CSS-px intent to wheel units: ~1px = 1 unit is too fine; use 120 per
  # ~100px so a 600px flick = ~6 notches spread across ticks.
  $wy = [int]([Math]::Sign($DeltaY) * [Math]::Max(15, [Math]::Abs($DeltaY * $frac * 120 / 100)))
  $wx = [int]([Math]::Sign($DeltaX) * [Math]::Max(15, [Math]::Abs($DeltaX * $frac * 120 / 100)))
  if ($DeltaY -ne 0) {
    # MOUSEEVENTF_WHEEL = 0x0800; negative = scroll up (away), positive = down.
    # Windows expects multiples of 120; we pass -wy because screen Y grows down.
    # dwData is declared `int`, not `uint`: PowerShell refuses to convert a
    # negative value to UInt32 at runtime ("Value was either too large or too
    # small"), which silently produced zero wheel events until this was fixed.
    [W.U]::mouse_event(0x0800, 0, 0, (-$wy), [System.UIntPtr]::Zero)
  }
  if ($DeltaX -ne 0) {
    # MOUSEEVENTF_HWHEEL = 0x1000 for horizontal.
    [W.U]::mouse_event(0x1000, 0, 0, $wx, [System.UIntPtr]::Zero)
  }
  # Inter-tick gap grows toward the tail (deceleration) + jitter.
  $gap = $rnd.Next(40, 140) * (1.0 + $i * 0.25) + $rnd.Next(0, 30)
  Start-Sleep -Milliseconds ([int]$gap)
  # Occasional coasting pause mid-flick.
  if ($Ticks -ge 4 -and $i -eq 1 -and $rnd.NextDouble() -lt 0.3) {
    Start-Sleep -Milliseconds $rnd.Next(150, 320)
  }
}

$ms = [int]([DateTime]::UtcNow - $t0).TotalMilliseconds
Write-Output "wheel delta=($DeltaX,$DeltaY) ticks=$Ticks ms=$ms seed=$Seed"
