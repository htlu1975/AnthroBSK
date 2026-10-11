<#
human-pointer.ps1 - Move the OS cursor along a human-like cubic Bezier path so
the page observes a real mousemove trajectory, optionally clicking at the end.

Why the API choice matters (measured on Windows, Chrome 155, bsk 0.3.2):

  SetCursorPos                 cursor moves, page receives NOTHING
  SendInput(MOUSEEVENTF_MOVE)  returns 1, silently discarded, cursor never moves
  mouse_event(...)             cursor moves AND the page receives real mousemove

All of them only reach the page while the Agent Window is the foreground window.
mouse_event delivers nothing to a background window, so this script locates the
Agent Window, forces it to the foreground, and verifies it got there before
moving anything. Chrome coalesces the stream, so a run yields fewer events than
the script sends - 43-52 `mousemove` events over 1.2-3.1 s at the defaults - and
the largest gaps land mid-path where the pointer is fastest, not at the ends.

`-Click` and `-Drag` need one thing done from the page first: bsk's
`browser-skill-overlay` sits in the hit-test path, so the button press lands on
the overlay and the page never sees it. Hide it once per page (and again after
every `bsk screenshot`) with:

  bsk evaluate --session <id> \
    'document.querySelector("browser-skill-overlay").setAttribute("data-bsk-capture-hidden","")'

Moving needs no such step - only the press is hit-tested. With the overlay
hidden, a measured `-Click` run produced 43-52 mousemove events over 1.2-3.1 s,
a 66-132 ms hold, pressure 0.5 while the button was down, and 0 untrusted events.

Coordinates are CSS viewport pixels. The OS works in physical pixels and the two
differ whenever the display is scaled or the page is zoomed, so the mapping is
measured from the real window tree rather than guessed:

  physical = renderWidgetRect.origin + css * (renderWidgetRect.size / viewportCss)

Usage:
  # move to the centre of a 1000x600 viewport and click there
  & human-pointer.ps1 -WindowTitleLike "My Page - Google Chrome" `
      -ViewportWidth 1000 -ViewportHeight 600 -EndCssX 500 -EndCssY 300 -Click

  # inspect what the script can see, without moving anything
  & human-pointer.ps1 -ListWindows

  # optional: -StartCssX -StartCssY -DurationMs -JitterPx -PauseChance
  #           -MaxPauseMs -NoOvershoot -Seed -ClickButton
#>
param(
  [string]$WindowTitleLike = "",
  [double]$ViewportWidth = 0,
  [double]$ViewportHeight = 0,
  [double]$EndCssX = 0,
  [double]$EndCssY = 0,
  [double]$StartCssX = -1,
  [double]$StartCssY = -1,
  [int]$DurationMs = 0,          # 0 = randomise 350-900 ms by distance
  [double]$JitterPx = 1.2,       # legacy white-noise per-step offset (kept for compat)
  [double]$TremorPx = 1.6,       # correlated hand-tremor amplitude (OU random walk)
  [double]$PauseChance = 0.06,   # probability of a micro-pause per step
  [int]$MaxPauseMs = 70,         # upper bound of a micro-pause
  [switch]$NoOvershoot,
  [switch]$Click,
  [switch]$Drag,                 # hold button during the path (drag-and-drop / slider)
  [ValidateSet('left', 'right', 'middle')][string]$ClickButton = 'left',
  [int]$DwellMsMin = 80,         # pre-click dwell: human pauses on target before pressing
  [int]$DwellMsMax = 250,
  [int]$Seed = 0,                # 0 = time-based seed
  [switch]$ListWindows
)

Add-Type -Namespace H -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool GetCursorPos(out P p);
[StructLayout(LayoutKind.Sequential)] public struct P { public int X; public int Y; }
[DllImport("user32.dll")] public static extern int GetSystemMetrics(int n);
[DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, System.UIntPtr e);
[DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, System.IntPtr l);
[DllImport("user32.dll")] public static extern bool EnumChildWindows(System.IntPtr h, EP cb, System.IntPtr l);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr h);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextW(System.IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassNameW(System.IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool GetWindowRect(System.IntPtr h, out R r);
[DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr h);
[DllImport("user32.dll")] public static extern bool BringWindowToTop(System.IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int cmd);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
[DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
[StructLayout(LayoutKind.Sequential)] public struct R { public int L; public int T; public int Rt; public int B; }
public delegate bool EP(System.IntPtr h, System.IntPtr l);

public static System.Collections.Generic.List<System.IntPtr> Found = new System.Collections.Generic.List<System.IntPtr>();
public static string Want = "";
public static bool TopCb(System.IntPtr h, System.IntPtr l) {
  if (!IsWindowVisible(h)) return true;
  var c = new System.Text.StringBuilder(256); GetClassNameW(h, c, 256);
  var t = new System.Text.StringBuilder(512); GetWindowTextW(h, t, 512);
  if (c.ToString() == "Chrome_WidgetWin_1" && t.ToString().Contains(Want)) Found.Add(h);
  return true;
}
public static System.Collections.Generic.List<System.IntPtr> Kids = new System.Collections.Generic.List<System.IntPtr>();
public static bool KidCb(System.IntPtr h, System.IntPtr l) {
  var c = new System.Text.StringBuilder(256); GetClassNameW(h, c, 256);
  if (c.ToString() == "Chrome_RenderWidgetHostHWND") Kids.Add(h);
  return true;
}
public static System.IntPtr FindTop(string want) {
  Found.Clear(); Want = want; EnumWindows(new EP(TopCb), System.IntPtr.Zero);
  return Found.Count > 0 ? Found[0] : System.IntPtr.Zero;
}
public static System.IntPtr FindWidget(System.IntPtr top) {
  // A Chrome window owns several Chrome_RenderWidgetHostHWND children: the page
  // viewport, the omnibox popup, a 1x1 helper. The viewport is the largest.
  Kids.Clear(); EnumChildWindows(top, new EP(KidCb), System.IntPtr.Zero);
  System.IntPtr best = System.IntPtr.Zero; long bestArea = -1;
  for (int i = 0; i < Kids.Count; i++) {
    R r; if (!GetWindowRect(Kids[i], out r)) continue;
    long a = (long)(r.Rt - r.L) * (r.B - r.T);
    if (a > bestArea) { bestArea = a; best = Kids[i]; }
  }
  return best;
}
public static string TitleOf(System.IntPtr h) {
  var t = new System.Text.StringBuilder(512); GetWindowTextW(h, t, 512); return t.ToString();
}
public static string RectStr(System.IntPtr h) {
  R r; if (!GetWindowRect(h, out r)) return "<none>";
  return "(" + r.L + "," + r.T + ")-(" + r.Rt + "," + r.B + ") " + (r.Rt - r.L) + "x" + (r.B - r.T);
}
'@

[void][H.U]::SetProcessDPIAware()

$rnd = if ($Seed -ne 0) { [System.Random]::new($Seed) } else { [System.Random]::new() }

function Get-WidgetRect([System.IntPtr]$h) {
  $r = [H.U+R]::new(); [void][H.U]::GetWindowRect($h, [ref]$r); return $r
}
function Move-Physical([int]$x, [int]$y) {
  # SendInput is discarded in this environment, so use the legacy API. Absolute
  # coordinates are normalised to 0..65535 across the whole virtual desktop.
  $vsX = [H.U]::GetSystemMetrics(76); $vsY = [H.U]::GetSystemMetrics(77)
  $vsW = [H.U]::GetSystemMetrics(78); $vsH = [H.U]::GetSystemMetrics(79)
  $nx = [int][Math]::Round(($x - $vsX) * 65535.0 / ($vsW - 1))
  $ny = [int][Math]::Round(($y - $vsY) * 65535.0 / ($vsH - 1))
  [H.U]::mouse_event(0x0001 -bor 0x8000 -bor 0x4000, $nx, $ny, 0, [System.UIntPtr]::Zero)
}
function Set-ForegroundVerified([System.IntPtr]$top, [int]$Attempts = 3) {
  for ($i = 1; $i -le $Attempts; $i++) {
    $fg = [H.U]::GetForegroundWindow()
    if ($fg -eq $top) { return $true }
    $fgPid = 0
    $fgTid = [H.U]::GetWindowThreadProcessId($fg, [ref]$fgPid)
    $myTid = [H.U]::GetCurrentThreadId()
    # SetForegroundWindow only succeeds for the process that already owns the
    # foreground window, so borrow that right by attaching our input queue to
    # the current foreground thread for the duration of the call.
    [void][H.U]::AttachThreadInput($myTid, $fgTid, $true)
    [void][H.U]::ShowWindow($top, 9)          # SW_RESTORE
    [void][H.U]::BringWindowToTop($top)
    [void][H.U]::SetForegroundWindow($top)
    [void][H.U]::AttachThreadInput($myTid, $fgTid, $false)
    Start-Sleep -Milliseconds 250
    if ([H.U]::GetForegroundWindow() -eq $top) { return $true }
  }
  return $false
}

if ($ListWindows) {
  Write-Output "virtualscreen origin=($([H.U]::GetSystemMetrics(76)),$([H.U]::GetSystemMetrics(77))) size=$([H.U]::GetSystemMetrics(78))x$([H.U]::GetSystemMetrics(79))"
  Write-Output "foreground: $([H.U]::TitleOf([H.U]::GetForegroundWindow()))"
  Write-Output ""
  [H.U]::Found.Clear(); [H.U]::Want = ""
  [void][H.U]::EnumWindows([H.U+EP] { param($h, $l) [H.U]::TopCb($h, $l) }, [System.IntPtr]::Zero)
  foreach ($h in [H.U]::Found) {
    Write-Output "TOP  $([H.U]::RectStr($h))  '$([H.U]::TitleOf($h))'"
    $w = [H.U]::FindWidget($h)
    if ($w -ne [System.IntPtr]::Zero) { Write-Output "     viewport widget $([H.U]::RectStr($w))" }
  }
  exit 0
}

if ([string]::IsNullOrWhiteSpace($WindowTitleLike)) { Write-Output "ERROR: -WindowTitleLike is required (run with -ListWindows to see candidates)"; exit 2 }
if ($ViewportWidth -le 0 -or $ViewportHeight -le 0) { Write-Output "ERROR: -ViewportWidth/-ViewportHeight (CSS px) are required"; exit 2 }

$top = [H.U]::FindTop($WindowTitleLike)
if ($top -eq [System.IntPtr]::Zero) { Write-Output "ERROR: no visible Chrome window whose title contains '$WindowTitleLike'"; exit 3 }
$wid = [H.U]::FindWidget($top)
if ($wid -eq [System.IntPtr]::Zero) { Write-Output "ERROR: no render widget under '$WindowTitleLike'"; exit 3 }

$r = Get-WidgetRect $wid
$scaleX = ($r.Rt - $r.L) / $ViewportWidth
$scaleY = ($r.B - $r.T) / $ViewportHeight
if ($scaleX -lt 0.4 -or $scaleX -gt 4 -or $scaleY -lt 0.4 -or $scaleY -gt 4) {
  Write-Output "ERROR: implausible scale ($scaleX,$scaleY). Check -ViewportWidth/-ViewportHeight against the real page."
  exit 4
}

$fgOk = Set-ForegroundVerified $top
Write-Output "window hwnd=$top viewport=$($r.L),$($r.T)-$($r.Rt),$($r.B) scale=($([Math]::Round($scaleX,4)),$([Math]::Round($scaleY,4))) foreground=$fgOk"
if (-not $fgOk) {
  Write-Output "ERROR: could not bring the Agent Window to the foreground. The page will receive no mouse events. Nothing was moved."
  exit 5
}

function To-PhysicalX([double]$css) { return [int][Math]::Round($r.L + $css * $scaleX) }
function To-PhysicalY([double]$css) { return [int][Math]::Round($r.T + $css * $scaleY) }

if ($StartCssX -lt 0 -or $StartCssY -lt 0) {
  # Start from wherever the cursor already is, expressed in viewport CSS pixels,
  # so the first leg of the path is continuous with the previous action.
  $p = [H.U+P]::new(); [void][H.U]::GetCursorPos([ref]$p)
  $StartCssX = ($p.X - $r.L) / $scaleX
  $StartCssY = ($p.Y - $r.T) / $scaleY
}

$startPX = To-PhysicalX $StartCssX; $startPY = To-PhysicalY $StartCssY
$endPX = To-PhysicalX $EndCssX; $endPY = To-PhysicalY $EndCssY
$dx = $endPX - $startPX; $dy = $endPY - $startPY
$dist = [Math]::Sqrt($dx * $dx + $dy * $dy)

switch ($ClickButton) {
  'left'   { $downCode = 0x0002; $upCode = 0x0004 }
  'right'  { $downCode = 0x0008; $upCode = 0x0010 }
  'middle' { $downCode = 0x0020; $upCode = 0x0040 }
}

if ($dist -lt 3) {
  Move-Physical $endPX $endPY
  Write-Output "already there ($startPX,$startPY) -> ($endPX,$endPY)"
}
else {
  # Duration: Fitts-like - longer for farther targets, randomised.
  if ($DurationMs -le 0) {
    $DurationMs = [int](280 + $dist * 0.9 + $rnd.Next(-60, 160))
    if ($DurationMs -lt 250) { $DurationMs = 250 }
    if ($DurationMs -gt 1400) { $DurationMs = 1400 }
  }

  $vsX = [H.U]::GetSystemMetrics(76); $vsY = [H.U]::GetSystemMetrics(77)
  $scrW = [H.U]::GetSystemMetrics(78); $scrH = [H.U]::GetSystemMetrics(79)

  $px = -$dy / $dist; $py = $dx / $dist
  $off1 = ($rnd.NextDouble() - 0.5) * 2 * [Math]::Min(140, $dist * 0.35)
  $off2 = ($rnd.NextDouble() - 0.5) * 2 * [Math]::Min(110, $dist * 0.28)
  $c1x = $startPX + $dx * 0.3 + $px * $off1; $c1y = $startPY + $dy * 0.3 + $py * $off1
  $c2x = $startPX + $dx * 0.72 + $px * $off2; $c2y = $startPY + $dy * 0.72 + $py * $off2

  function B([double]$t, [double]$a, [double]$b, [double]$c, [double]$d) {
    $m = 1 - $t
    return $m*$m*$m*$a + 3*$m*$m*$t*$b + 3*$m*$t*$t*$c + $t*$t*$t*$d
  }
  function MinJerk([double]$t) {
    # Minimum-jerk velocity profile: bell-shaped speed, gentle landing.
    return 10*$t*$t*$t - 15*$t*$t*$t*$t + 6*$t*$t*$t*$t*$t
  }

  $steps = [int]([Math]::Max(18, [Math]::Min(140, $dist / 4)))

  # Optional human overshoot: fly slightly past, settle back on the last 25%.
  $ox = $endPX; $oy = $endPY
  if (-not $NoOvershoot -and $rnd.NextDouble() -lt 0.55) {
    $oMag = [Math]::Min(30, $dist * 0.08) * (0.6 + $rnd.NextDouble() * 0.8)
    $ox += ($dx / $dist) * $oMag; $oy += ($dy / $dist) * $oMag
  }

  # Correlated hand tremor (Ornstein-Uhlenbeck walk) + small white jitter.
  $trx = 0.0; $try = 0.0

  if ($Drag) {
    Move-Physical $startPX $startPY
    Start-Sleep -Milliseconds $rnd.Next(120, 280)  # grip pause before drag
    [H.U]::mouse_event($downCode, 0, 0, 0, [System.UIntPtr]::Zero)
    Start-Sleep -Milliseconds $rnd.Next(80, 180)
  }

  $t0 = [DateTime]::UtcNow
  for ($i = 0; $i -le $steps; $i++) {
    $t = $i / $steps
    $e = MinJerk $t

    if ($e -lt 0.75) {
      $bx = B $e $startPX $c1x $c2x $ox; $by = B $e $startPY $c1y $c2y $oy
    }
    else {
      # correction leg: Bezier from the ~75% curve point to the exact endpoint
      $q = ($e - 0.75) / 0.25
      $sx = B 0.75 $startPX $c1x $c2x $ox; $sy = B 0.75 $startPY $c1y $c2y $oy
      $qx = $sx + ($endPX - $sx) * 0.4; $qy = $sy + ($endPY - $sy) * 0.4
      $bx = ((1-$q)*(1-$q)*$sx + 2*(1-$q)*$q*$qx + $q*$q*$endPX)
      $by = ((1-$q)*(1-$q)*$sy + 2*(1-$q)*$q*$qy + $q*$q*$endPY)
    }

    # OU update: mean-reverting drift plus Gaussian kick.
    $u1 = [Math]::Max(1e-6, $rnd.NextDouble()); $u2 = $rnd.NextDouble()
    $gauss = [Math]::Sqrt(-2.0 * [Math]::Log($u1)) * [Math]::Cos(2.0 * [Math]::PI * $u2)
    $u3 = [Math]::Max(1e-6, $rnd.NextDouble()); $u4 = $rnd.NextDouble()
    $gauss2 = [Math]::Sqrt(-2.0 * [Math]::Log($u3)) * [Math]::Cos(2.0 * [Math]::PI * $u4)
    $trx = $trx * 0.85 + $gauss * $TremorPx * 0.35
    $try = $try * 0.85 + $gauss2 * $TremorPx * 0.35
    if ($trx -gt 6) { $trx = 6 }; if ($trx -lt -6) { $trx = -6 }
    if ($try -gt 6) { $try = 6 }; if ($try -lt -6) { $try = -6 }
    $cx = $bx + $trx + ($rnd.NextDouble() - 0.5) * 2 * $JitterPx * 0.5
    $cy = $by + $try + ($rnd.NextDouble() - 0.5) * 2 * $JitterPx * 0.5
    $cx = [Math]::Max($vsX, [Math]::Min($vsX + $scrW - 1, $cx))
    $cy = [Math]::Max($vsY, [Math]::Min($vsY + $scrH - 1, $cy))
    Move-Physical ([int][Math]::Round($cx)) ([int][Math]::Round($cy))

    $target = $t0.AddMilliseconds($DurationMs * $t)
    $sleep = [int]($target - [DateTime]::UtcNow).TotalMilliseconds
    if ($sleep -gt 1) { Start-Sleep -Milliseconds $sleep }

    # random micro-pause (hand hesitations), longer rare dwell near the middle
    if ($rnd.NextDouble() -lt $PauseChance) {
      $pause = $rnd.Next(15, $MaxPauseMs + 1)
      if ($t -gt 0.35 -and $t -lt 0.65 -and $rnd.NextDouble() -lt 0.25) { $pause += $rnd.Next(60, 160) }
      Start-Sleep -Milliseconds $pause
    }
    if ($rnd.NextDouble() -lt 0.015) { Start-Sleep -Milliseconds $rnd.Next(120, 260) }  # rare stumble
  }

  Move-Physical $endPX $endPY
  Write-Output "path css=($([int]$StartCssX),$([int]$StartCssY))->($([int]$EndCssX),$([int]$EndCssY)) physical=($startPX,$startPY)->($endPX,$endPY) steps=$steps ms=$([int]([DateTime]::UtcNow - $t0).TotalMilliseconds) profile=minjerk tremor=$TremorPx"
}

if ($Drag) {
  Start-Sleep -Milliseconds $rnd.Next(80, 200)  # settle at drop point while holding
  [H.U]::mouse_event($upCode, 0, 0, 0, [System.UIntPtr]::Zero)
  Write-Output "drag button=$ClickButton released at=($endPX,$endPY)"
}
elseif ($Click) {
  # Human dwell: pause on target before pressing, then hold like a finger.
  $dwell = $rnd.Next($DwellMsMin, $DwellMsMax + 1)
  Start-Sleep -Milliseconds $dwell
  $holdMs = $rnd.Next(45, 130)
  [H.U]::mouse_event($downCode, 0, 0, 0, [System.UIntPtr]::Zero)
  Start-Sleep -Milliseconds $holdMs
  [H.U]::mouse_event($upCode, 0, 0, 0, [System.UIntPtr]::Zero)
  Write-Output "click button=$ClickButton dwell=${dwell}ms hold=${holdMs}ms"
}
