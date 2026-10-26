# BikeComputer - capture a crash, fully automatic (one double-click). Run via CAPTURE-CRASH.bat.
# What it does: finds the board's USB port, asks you once, restarts the board ONE time through the USB cable (the same
# reset esptool uses; nothing is written to the board), then records everything the board prints for up to 4 minutes,
# notices crashes ("Guru Meditation", "Backtrace") by itself and saves the file for Claude. It never flashes or erases.
param([int]$Minutes = 4)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$log = Join-Path $PSScriptRoot "crash-log-$stamp.txt"
Write-Host ""
Write-Host "  BIKECOMPUTER CRASH CAPTURE" -ForegroundColor Cyan
Write-Host "  --------------------------"
$port = (Get-CimInstance Win32_PnPEntity | Where-Object { $_.Name -match 'CH34|USB-Enhanced|USB Serial|USB Single Serial' -and $_.Name -match '\((COM[0-9]+)\)' } |
         ForEach-Object { if ($_.Name -match '\((COM[0-9]+)\)') { $matches[1] } } | Select-Object -First 1)
if (-not $port) { Write-Host "  The board was not found on any USB port (check the cable)." -ForegroundColor Red; Read-Host "  Press Enter to close"; exit 1 }
Write-Host "  Board found on $port." -ForegroundColor Green
Write-Host ""
Write-Host "  Before you continue: keep your iPhone next to the board with Cyclift OPEN (it connects by itself),"
Write-Host "  and if the crash happened with the power meter, be ready to turn the cranks once the board has started."
Write-Host "  The board will restart ONE time. Nothing is written to it."
$ok = Read-Host "  Type YES and press Enter to start"
if ($ok -ne 'YES') { Write-Host "  Cancelled - nothing was done."; Read-Host "  Press Enter to close"; exit 0 }

$sp = New-Object System.IO.Ports.SerialPort $port, 115200, 'None', 8, 'One'
$sp.ReadTimeout = 300; $sp.DtrEnable = $false; $sp.RtsEnable = $false
try { $sp.Open() } catch { Write-Host "  Could not open $port - close any other program using it and try again." -ForegroundColor Red; Read-Host "  Press Enter to close"; exit 1 }
"BikeComputer crash capture $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') on $port" | Out-File $log -Encoding utf8
# one reset: EN low for 150 ms with IO0 high (DTR off) = normal boot, not download mode
$sp.RtsEnable = $true; Start-Sleep -Milliseconds 150; $sp.RtsEnable = $false
"--- board restarted by the capture tool ---" | Out-File $log -Append -Encoding utf8
Write-Host ""
Write-Host "  Recording... (up to $Minutes minutes; it stops early 30 s after the third crash)" -ForegroundColor Cyan
$end = (Get-Date).AddMinutes($Minutes); $crashes = 0; $stopAt = $null; $lines = 0
try {
  while ((Get-Date) -lt $end -and (-not $stopAt -or (Get-Date) -lt $stopAt)) {
    try { $line = $sp.ReadLine() } catch [System.TimeoutException] { continue }
    $lines++
    ((Get-Date -Format 'HH:mm:ss.fff') + ' ' + $line.TrimEnd("`r")) | Out-File $log -Append -Encoding utf8
    if ($line -match 'Guru Meditation|abort\(\) was called|Stack canary|stack overflow|Task watchdog got triggered|LoadProhibited|StoreProhibited|InstrFetchProhibited|IllegalInstruction') {
      $crashes++; Write-Host ("  Crash {0} recorded." -f $crashes) -ForegroundColor Yellow
      if ($crashes -ge 3 -and -not $stopAt) { $stopAt = (Get-Date).AddSeconds(30) }
    }
    if ($line -match 'SAFE MODE') { Write-Host "  The board entered safe mode." -ForegroundColor Yellow; if (-not $stopAt) { $stopAt = (Get-Date).AddSeconds(10) } }
  }
} finally { $sp.Close() }
"--- end: $lines lines, $crashes crash(es) ---" | Out-File $log -Append -Encoding utf8
Write-Host ""
if ($crashes -gt 0) { Write-Host "  Done: $crashes crash(es) captured in $(Split-Path $log -Leaf). Tell Claude: 'crash log saved'." -ForegroundColor Green }
elseif ($lines -gt 0) { Write-Host "  Done: no crash happened in $Minutes minutes ($lines lines saved in $(Split-Path $log -Leaf)). Tell Claude: 'no crash'." -ForegroundColor Green }
else { Write-Host "  The board printed nothing - the cable may be charge-only, or another program used the port. Tell Claude." -ForegroundColor Red }
Read-Host "  Press Enter to close"
