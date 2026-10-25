# Bike Computer - restore the EXACT image saved by INSTALL-v0.6.1 (the firmware that was on the board + your settings + rides as they were).
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
function Stop-With($msg) { Write-Host ""; Write-Host "  STOPPED: $msg" -ForegroundColor Red; Read-Host "  Press Enter to close"; exit 1 }
Write-Host ""; Write-Host "  RESTORE THE BACKUP TAKEN BEFORE 0.6.1" -ForegroundColor Cyan
$files = Get-ChildItem 'backup-before-v061-*.bin' | Sort-Object LastWriteTime -Descending
if (-not $files) { Stop-With "no backup-before-v061-*.bin file found." }
$pre = $files[0].Name
if ((Get-Item $pre).Length -ne 16777216) { Stop-With "$pre is not 16 MB." }
Write-Host "  Using $pre (newest). This writes the whole 16 MB: the previous firmware AND settings/rides as they were then."
Write-Host "  Rides recorded after that backup will be lost - export them first if you want them."
$port = (Get-CimInstance Win32_PnPEntity | Where-Object { $_.Name -match 'CH34|USB-Enhanced|USB Serial|USB Single Serial' -and $_.Name -match '\((COM[0-9]+)\)' } |
         ForEach-Object { if ($_.Name -match '\((COM[0-9]+)\)') { $matches[1] } } | Select-Object -First 1)
if (-not $port) { Stop-With "the Waveshare was not found on any USB port." }
$ok = Read-Host "  Type RESTORE and press Enter to continue"
if ($ok -ne 'RESTORE') { Write-Host "  Cancelled."; Read-Host "  Press Enter to close"; exit 0 }
$log = 'restore-before-v061-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt'
& cmd /c ".\esptool.exe --chip esp32s3 -p $port -b 460800 write-flash 0x0 $pre 2>&1" | ForEach-Object { $_ | Out-File $log -Append -Encoding utf8; Write-Host "  $_" }
if ($LASTEXITCODE -eq 0) { Write-Host "  RESTORED and verified. The board restarts by itself." -ForegroundColor Green } else { Write-Host "  esptool reported a problem - send $log to Claude." -ForegroundColor Red }
Read-Host "  Press Enter to close"
