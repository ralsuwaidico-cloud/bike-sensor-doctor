# Bike Computer - go back to firmware 0.7.3 (keeps settings and rides). Run via ROLLBACK-TO-v073.bat.
# The partition table is left as it is (both table versions work with 0.7.3). WARNING: 0.7.3 aborts at EVERY start on the owner's board (Bluetooth start, 27 Oct) - use RESTORE-CHOSEN-BACKUP.bat
# to go back; run this only if Claude asks.
# Writes only the OTA selector (0xf000) and the 0.7.3 app (0x20000) from fw-v0.7.3, after checking their checksums.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
function Stop-With($msg) { Write-Host ""; Write-Host "  STOPPED: $msg" -ForegroundColor Red; Write-Host "  Nothing was changed on the board."; Read-Host "  Press Enter to close"; exit 1 }
Write-Host ""; Write-Host "  ROLL BACK TO FIRMWARE 0.7.3 (settings and rides are kept)" -ForegroundColor Cyan
Write-Host "  WARNING: on your board 0.7.3 stops at EVERY start (Bluetooth start). To go back, use RESTORE-CHOSEN-BACKUP.bat;" -ForegroundColor Red
Write-Host "  continue here only if Claude asked for it." -ForegroundColor Red
$fw = @(
  @{ off = '0xf000';  file = 'fw-v0.7.3\BC073-otadata.bin'; sha = '7d2c7ac4888bfd75cd5f56e8d61f69595121183afc81556c876732fd3782c62f' },
  @{ off = '0x20000'; file = 'fw-v0.7.3\BC073-app.bin';     sha = '181b2e5c751108679a2101bfb1c1942b0302fe537527ceaeba207c5256ea4da5' }
)
foreach ($f in $fw) {
  if (-not (Test-Path $f.file)) { Stop-With "$($f.file) is missing." }
  if ((Get-FileHash $f.file -Algorithm SHA256).Hash.ToLower() -ne $f.sha) { Stop-With "$($f.file) does not match its checksum." }
  Write-Host ("  OK  {0,-34} checksum matches" -f $f.file) -ForegroundColor Green
}
if (-not (Test-Path '.\esptool.exe')) { Stop-With "esptool.exe is missing." }
$port = (Get-CimInstance Win32_PnPEntity | Where-Object { $_.Name -match 'CH34|USB-Enhanced|USB Serial|USB Single Serial' -and $_.Name -match '\((COM[0-9]+)\)' } |
         ForEach-Object { if ($_.Name -match '\((COM[0-9]+)\)') { $matches[1] } } | Select-Object -First 1)
if (-not $port) { Stop-With "the Waveshare was not found on any USB port." }
Write-Host "  Waveshare found on $port" -ForegroundColor Green
$ok = Read-Host "  Type YES and press Enter to install 0.7.3, anything else to cancel"
if ($ok -ne 'YES') { Write-Host "  Cancelled - nothing was changed."; Read-Host "  Press Enter to close"; exit 0 }
$log = 'rollback-v073-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt'
$eargs = "--chip esp32s3 -p $port -b 460800 write-flash"
foreach ($f in $fw) { $eargs += " $($f.off) $($f.file)" }
& cmd /c ".\esptool.exe $eargs 2>&1" | ForEach-Object { $_ | Out-File $log -Append -Encoding utf8; Write-Host "  $_" }
if ($LASTEXITCODE -eq 0) { Write-Host "  DONE. Firmware 0.7.3 written and verified; the board restarts by itself." -ForegroundColor Green } else { Write-Host "  esptool reported a problem - send $log to Claude." -ForegroundColor Red }
Read-Host "  Press Enter to close"
