# Bike Computer 0.7.2 - record the device's serial log for the first hardware test (read only, nothing is sent to the board).
# What Claude looks for: lines tagged 'pipe', e.g. 'pipe: power → SUBSCRIBED (cccd 0x0023 read back 01 00 ...)' and 'pipe: power → VALID 142 W'.

# Every line is saved immediately to device-log-v072-<time>.txt, so you can stop at any moment with Ctrl+C or by closing the window.

param([int]$Minutes = 3)

$log = Join-Path $PSScriptRoot ('device-log-v072-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')

$port = (Get-CimInstance Win32_PnPEntity | Where-Object { $_.Name -match 'CH34|USB-Enhanced|USB Serial' -and $_.Name -match '\((COM[0-9]+)\)' } | ForEach-Object { if ($_.Name -match '\((COM[0-9]+)\)') { $matches[1] } } | Select-Object -First 1)

if (-not $port) { Write-Host "Waveshare not found on any COM port." -ForegroundColor Red; Read-Host "Press Enter"; exit 1 }

Write-Host "Recording $port for up to $Minutes minutes into $log" -ForegroundColor Cyan

Write-Host "1. Press RESET on the board now (captures the start-up)." -ForegroundColor Cyan
Write-Host "2. Pedal the bike so the power meter wakes, and keep pedalling for a minute." -ForegroundColor Cyan
Write-Host "3. Leave it running; it stops by itself after $Minutes minutes (or close the window)." -ForegroundColor Cyan

$sp = New-Object System.IO.Ports.SerialPort $port, 115200, 'None', 8, 'One'

$sp.DtrEnable = $false; $sp.RtsEnable = $false; $sp.ReadTimeout = 500

"Device log $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') on $port" | Out-File $log -Encoding utf8

try { $sp.Open() } catch { Write-Host "Could not open $port (is another program using it?)" -ForegroundColor Red; Read-Host "Press Enter"; exit 1 }

$end = (Get-Date).AddMinutes($Minutes)

try {

  while ((Get-Date) -lt $end) { try { $line = $sp.ReadLine(); ((Get-Date -Format 'HH:mm:ss') + ' ' + $line) | Out-File $log -Append -Encoding utf8; Write-Host $line } catch [System.TimeoutException] {} }

} finally { $sp.Close() }

Write-Host "Saved $log - tell Claude it is done." -ForegroundColor Green

Start-Sleep -Seconds 3

