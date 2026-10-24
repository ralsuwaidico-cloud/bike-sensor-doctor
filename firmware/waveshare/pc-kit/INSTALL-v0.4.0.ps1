# Bike Computer - install firmware 0.4.0 (phone link + sensor sources). Run via INSTALL-v0.4.0.bat.
# Safety, in this order:
#   1. factory backup must be present (16 MB);
#   2. every 0.4.0 file must match its SHA-256;
#   3. a COMPLETE 16 MB backup of the board as it is now (firmware 0.3.0 + settings + rides) is read to
#      backup-before-v040-<time>.bin and checked (size, and the 0.3.0 app found inside at 0x20000);
#   4. you type YES;
#   5. ONLY bootloader, partition table, OTA selector and app are written. Settings (NVS) and rides (FAT) are not touched.
# Roll back: INSTALL-v0.3.0.bat (firmware 0.3.0, keeps data) or RESTORE-BACKUP-BEFORE-v040.bat (exact image incl. data).
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
function Stop-With($msg) { Write-Host ""; Write-Host "  STOPPED: $msg" -ForegroundColor Red; Write-Host "  Nothing was changed on the board."; Read-Host "  Press Enter to close"; exit 1 }
Write-Host ""
Write-Host "  INSTALL BIKE COMPUTER FIRMWARE 0.4.0" -ForegroundColor Cyan
Write-Host "  ------------------------------------"
$bk = Join-Path $PSScriptRoot 'factory_backup_16MB.bin'
if (-not (Test-Path $bk)) { Stop-With "factory_backup_16MB.bin is not in this folder." }
if ((Get-Item $bk).Length -ne 16777216) { Stop-With "factory_backup_16MB.bin is not 16 MB - the backup looks damaged." }
Write-Host "  Factory backup present (16 MB) - kept untouched." -ForegroundColor Green
$fw = @(
  @{ off = '0x0';     file = 'fw-v0.4.0\BC040-bootloader.bin'; sha = 'de894772ccc6b4e0908608aaa4fb0e138bdb533354f90b42d9c1075eca0e724b' },
  @{ off = '0x8000';  file = 'fw-v0.4.0\BC040-partitions.bin'; sha = '812e16cc1b709a18f7d791de3b2d2f7abec36831edf2ba058e205fb42d603fe6' },
  @{ off = '0xf000';  file = 'fw-v0.4.0\BC040-otadata.bin';    sha = '7d2c7ac4888bfd75cd5f56e8d61f69595121183afc81556c876732fd3782c62f' },
  @{ off = '0x20000'; file = 'fw-v0.4.0\BC040-app.bin';        sha = 'b181796f1df4b6de47eea32661ee2f5dd1683ab9bcdd3119a67a4d6e61c5eb0b' }
)
foreach ($f in $fw) {
  if (-not (Test-Path $f.file)) { Stop-With "$($f.file) is missing." }
  $h = (Get-FileHash $f.file -Algorithm SHA256).Hash.ToLower()
  if ($h -ne $f.sha) { Stop-With "$($f.file) does not match its checksum (download damaged?)." }
  Write-Host ("  OK  {0,-34} {1,9} bytes  checksum matches" -f $f.file, (Get-Item $f.file).Length) -ForegroundColor Green
}
if (-not (Test-Path '.\esptool.exe')) { Stop-With "esptool.exe is missing." }
# rollback kit must be complete before we start
if (-not (Test-Path 'INSTALL-v0.3.0.bat') -or -not (Test-Path 'fw-v0.3.0\BC030-app.bin')) { Stop-With "the 0.3.0 rollback files (INSTALL-v0.3.0.bat, fw-v0.3.0) are missing." }
if ((Get-FileHash 'fw-v0.3.0\BC030-app.bin' -Algorithm SHA256).Hash.ToLower() -ne '5dac7db7d6747f70d36809dd2255439b93336631451906d20e6ac9364266f7d2') { Stop-With "fw-v0.3.0\BC030-app.bin is damaged - rollback would not be possible." }
Write-Host "  Rollback to 0.3.0 available (INSTALL-v0.3.0.bat, checksum OK)." -ForegroundColor Green
$port = (Get-CimInstance Win32_PnPEntity | Where-Object { $_.Name -match 'CH34|USB-Enhanced|USB Serial|USB Single Serial' -and $_.Name -match '\((COM[0-9]+)\)' } |
         ForEach-Object { if ($_.Name -match '\((COM[0-9]+)\)') { $matches[1] } } | Select-Object -First 1)
if (-not $port) { Stop-With "the Waveshare was not found on any USB port (check the cable)." }
Write-Host "  Waveshare found on $port" -ForegroundColor Green
# 3. full backup of the board as it is now
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$pre = "backup-before-v040-$stamp.bin"
$log = "install-v040-$stamp.txt"
"Install 0.4.0 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') on $port" | Out-File $log -Encoding utf8
Write-Host ""
Write-Host "  Reading a complete backup of the board (16 MB, about 3 minutes): $pre" -ForegroundColor Cyan
& cmd /c ".\esptool.exe --chip esp32s3 -p $port -b 921600 read-flash 0x0 0x1000000 $pre 2>&1" | ForEach-Object { $_ | Out-File $log -Append -Encoding utf8; Write-Host "  $_" }
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $pre)) { Stop-With "the backup could not be read (see $log). Installation not started." }
if ((Get-Item $pre).Length -ne 16777216) { Stop-With "the backup is not 16 MB - installation not started." }
# the backup must contain the 0.3.0 app at 0x20000 (proves the board is on 0.3.0 and the dump is good)
$fs = [System.IO.File]::OpenRead((Resolve-Path $pre)); $buf = New-Object byte[] 1676496; $fs.Seek(0x20000, 'Begin') | Out-Null; $fs.Read($buf, 0, $buf.Length) | Out-Null; $fs.Close()
$sha = [System.Security.Cryptography.SHA256]::Create(); $h = ([BitConverter]::ToString($sha.ComputeHash($buf)) -replace '-', '').ToLower()
if ($h -ne '5dac7db7d6747f70d36809dd2255439b93336631451906d20e6ac9364266f7d2') { Stop-With "the backup does not contain firmware 0.3.0 at 0x20000 (found $h). Tell Claude before installing." }
Write-Host "  Backup verified: 16 MB, firmware 0.3.0 + settings + rides saved in $pre" -ForegroundColor Green
"Backup $pre verified (0.3.0 app hash matches)" | Out-File $log -Append -Encoding utf8
Write-Host ""
Write-Host "  This installs 0.4.0. Your settings and saved rides are kept."
Write-Host "  To go back later: INSTALL-v0.3.0.bat (0.3.0, keeps data) or RESTORE-BACKUP-BEFORE-v040.bat (exact image)."
$ok = Read-Host "  Type YES and press Enter to install, anything else to cancel"
if ($ok -ne 'YES') { Write-Host "  Cancelled - nothing was changed (the backup file is kept)."; Read-Host "  Press Enter to close"; exit 0 }
$eargs = "--chip esp32s3 -p $port -b 460800 write-flash"
foreach ($f in $fw) { $eargs += " $($f.off) $($f.file)" }
& cmd /c ".\esptool.exe $eargs 2>&1" | ForEach-Object { $_ | Out-File $log -Append -Encoding utf8; Write-Host "  $_" }
$code = $LASTEXITCODE
"esptool exit code: $code" | Out-File $log -Append -Encoding utf8
Write-Host ""
if ($code -eq 0) { Write-Host "  INSTALLED. 4 regions written and verified. The board restarts by itself." -ForegroundColor Green }
else { Write-Host "  esptool reported a problem (exit code $code). Run INSTALL-v0.3.0.bat to go back; send $log to Claude." -ForegroundColor Red }
Write-Host "  Log saved as $log"
Read-Host "  Press Enter to close"
