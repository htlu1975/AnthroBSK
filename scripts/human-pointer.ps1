<#
human-pointer.ps1 - Move the Windows cursor along a human-like cubic Bezier
path with variable speed, jitter, overshoot-and-correct, and random micro
pauses. Generates real WM_MOUSEMOVE events, so pages' mousemove listeners
see a natural pointer trajectory.

Usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File human-pointer.ps1 -EndX 800 -EndY 500
  Optional: -StartX -StartY -DurationMs -JitterPx -PauseChance -MaxPauseMs -Overshoot -Seed

Coordinates are SCREEN pixels. The target browser window must be visible
(not minimized) for the page to receive the events.
#>
param(
  [double]$StartX = -1,
  [double]$StartY = -1,
  [Parameter(Mandatory = $true)][double]$EndX,
  [Parameter(Mandatory = $true)][double]$EndY,
  [int]$DurationMs = 0,          # 0 = randomize 350-900 ms by distance
  [double]$JitterPx = 1.2,       # per-step random offset
  [double]$PauseChance = 0.06,   # probability of a micro-pause per step
  [int]$MaxPauseMs = 70,         # upper bound of a micro-pause
  [switch]$NoOvershoot,
  [int]$Seed = 0                 # 0 = time-based seed
)

Add-Type -Namespace H -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
[DllImport("user32.dll")] public static extern bool GetCursorPos(out P p);
[StructLayout(LayoutKind.Sequential)] public struct P { public int X; public int Y; }
[DllImport("user32.dll")] public static extern int GetSystemMetrics(int n);
'@
[void][H.U]::SetProcessDPIAware()   # physical pixels; without this a scaled
                                     # monitor virtualizes every coordinate

$rnd = if ($Seed -ne 0) { [System.Random]::new($Seed) } else { [System.Random]::new() }

if ($StartX -lt 0 -or $StartY -lt 0) {
  $p = [H.U+P]::new()
  [void][H.U]::GetCursorPos([ref]$p)
  $StartX = $p.X; $StartY = $p.Y
}

$dx = $EndX - $StartX; $dy = $EndY - $StartY
$dist = [Math]::Sqrt($dx * $dx + $dy * $dy)
if ($dist -lt 3) { [void][H.U]::SetCursorPos([int]$EndX, [int]$EndY); Write-Output "already there ($([int]$StartX),$([int]$StartY)) -> ($([int]$EndX),$([int]$EndY))"; exit 0 }

# Duration: Fitts-like - longer for farther targets, randomized.
if ($DurationMs -le 0) {
  $DurationMs = [int](280 + $dist * 0.9 + $rnd.Next(-60, 160))
  if ($DurationMs -lt 250) { $DurationMs = 250 }; if ($DurationMs -gt 1400) { $DurationMs = 1400 }
}

# Screen bounds clamp helper values
$scrW = [H.U]::GetSystemMetrics(0); $scrH = [H.U]::GetSystemMetrics(1)

# Perpendicular unit vector for control-point offsets
$px = -$dy / $dist; $py = $dx / $dist
# Two random control points: bell-ish offsets on both sides of the line.
$off1 = ($rnd.NextDouble() - 0.5) * 2 * [Math]::Min(140, $dist * 0.35)
$off2 = ($rnd.NextDouble() - 0.5) * 2 * [Math]::Min(110, $dist * 0.28)
$c1x = $StartX + $dx * 0.3 + $px * $off1; $c1y = $StartY + $dy * 0.3 + $py * $off1
$c2x = $StartX + $dx * 0.72 + $px * $off2; $c2y = $StartY + $dy * 0.72 + $py * $off2

function B([double]$t, [double]$a, [double]$b, [double]$c, [double]$d) {
  $m = 1 - $t
  return $m*$m*$m*$a + 3*$m*$m*$t*$b + 3*$m*$t*$t*$c + $t*$t*$t*$d
}

# Step count scales with distance; min interval ~8ms to stay smooth.
$steps = [int]([Math]::Max(18, [Math]::Min(140, $dist / 4)))

# Optional human overshoot: fly slightly past, settle back on the last 25%.
$ox = $EndX; $oy = $EndY
if (-not $NoOvershoot -and $rnd.NextDouble() -lt 0.55) {
  $oMag = [Math]::Min(30, $dist * 0.08) * (0.6 + $rnd.NextDouble() * 0.8)
  $ox += ($dx / $dist) * $oMag; $oy += ($dy / $dist) * $oMag
}

$t0 = [DateTime]::UtcNow
for ($i = 0; $i -le $steps; $i++) {
  $t = $i / $steps
  # ease-in-out (smoothstep-like), slightly asymmetric: quick start, gentle landing
  $e = $t * $t * (3 - 2 * $t); $e = $e * (0.85 + 0.3 * $t)
  if ($e -gt 1) { $e = 1 }

  if ($e -lt 0.75) {
    $bx = B $e $StartX $c1x $c2x $ox; $by = B $e $StartY $c1y $c2y $oy
  } else {
    # correction leg: Bezier from ~75% curve point to exact endpoint
    $q = ($e - 0.75) / 0.25
    $sx = B 0.75 $StartX $c1x $c2x $ox; $sy = B 0.75 $StartY $c1y $c2y $oy
    $qx = $sx + ($EndX - $sx) * 0.4; $qy = $sy + ($EndY - $sy) * 0.4
    $bx = ((1-$q)*(1-$q)*$sx + 2*(1-$q)*$q*$qx + $q*$q*$EndX)
    $by = ((1-$q)*(1-$q)*$sy + 2*(1-$q)*$q*$qy + $q*$q*$EndY)
  }

  $cx = $bx + ($rnd.NextDouble() - 0.5) * 2 * $JitterPx
  $cy = $by + ($rnd.NextDouble() - 0.5) * 2 * $JitterPx
  $cx = [Math]::Max(0, [Math]::Min($scrW - 1, $cx)); $cy = [Math]::Max(0, [Math]::Min($scrH - 1, $cy))
  [void][H.U]::SetCursorPos([int][Math]::Round($cx), [int][Math]::Round($cy))

  # pacing: target wall-clock time for this step
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

[void][H.U]::SetCursorPos([int][Math]::Round($EndX), [int][Math]::Round($EndY))
$ms = [int]([DateTime]::UtcNow - $t0).TotalMilliseconds
Write-Output "ok path=($([int]$StartX),$([int]$StartY))->($([int]$EndX),$([int]$EndY)) steps=$steps ms=$ms"
