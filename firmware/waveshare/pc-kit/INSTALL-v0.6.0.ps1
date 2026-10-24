# Bike Computer - install firmware 0.6.0 (0.5.0 + connected standby, Quick Settings handle, Wi-Fi page, phone services). Run via INSTALL-v0.6.0.bat.
# Safety, in this order:
#   1. factory backup must be present (16 MB);
#   2. every 0.6.0 file must match its SHA-256; the 0.5.0 rollback files must be present and intact;
#   3. a COMPLETE 16 MB backup of the board as it is now (firmware + settings + rides) is read to
#      backup-before-v060-<time>.bin and checked: size, and the app found inside at 0x20000 must be firmware 0.5.0
#      (or 0.4.0) with a matching checksum - so the backup is proven good before anything is written;
#   4. you type YES;
#   5. ONLY the OTA selector (0xf000) and the app (0x20000) are written. Bootloader and partition table are
#      byte-identical to 0.5.0 and are left alone. Settings (NVS) and rides (FAT) are not touched.
# Roll back: ROLLBACK-TO-v050.bat (firmware 0.5.0, keeps data) or RESTORE-BACKUP-BEFORE-v060.bat (exact image incl. data).
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
function Stop-With($msg) { Write-Host ""; Write-Host "  STOPPED: $msg" -ForegroundColor Red; Write-Host "  Nothing was changed on the board."; Read-Host "  Press Enter to close"; exit 1 }
Write-Host ""
Write-Host "  INSTALL BIKE COMPUTER FIRMWARE 0.6.0 (standby + Wi-Fi + phone services)" -ForegroundColor Cyan
Write-Host "  -----------------------------------------------------------------------"
$bk = Join-Path $PSScriptRoot 'factory_backup_16MB.bin'
if (-not (Test-Path $bk)) { Stop-With "factory_backup_16MB.bin is not in this folder." }
if ((Get-Item $bk).Length -ne 16777216) { Stop-With "factory_backup_16MB.bin is not 16 MB - the backup looks damaged." }
Write-Host "  Factory backup present (16 MB) - kept untouched." -ForegroundColor Green
$fw = @(
  @{ off = '0xf000';  file = 'fw-v0.6.0\BC060-otadata.bin'; sha = '7d2c7ac4888bfd75cd5f56e8d61f69595121183afc81556c876732fd3782c62f' },
  @{ off = '0x20000'; file = 'fw-v0.6.0\BC060-app.bin';     sha = 'cdecb1f4b28d6b5aaaed770b7879dfe3e85a520fad29fbc50bb112c70f738139' }
)
$same = @(   # shipped for completeness; identical to 0.5.0, so they are verified but NOT written
  @{ file = 'fw-v0.6.0\BC060-bootloader.bin'; sha = 'de894772ccc6b4e0908608aaa4fb0e138bdb533354f90b42d9c1075eca0e724b' },
  @{ file = 'fw-v0.6.0\BC060-partitions.bin'; sha = '812e16cc1b709a18f7d791de3b2d2f7abec36831edf2ba058e205fb42d603fe6' }
)
foreach ($f in ($fw + $same)) {
  if (-not (Test-Path $f.file)) { Stop-With "$($f.file) is missing." }
  $h = (Get-FileHash $f.file -Algorithm SHA256).Hash.ToLower()
  if ($h -ne $f.sha) { Stop-With "$($f.file) does not match its checksum (download damaged?)." }
  Write-Host ("  OK  {0,-34} {1,9} bytes  checksum matches" -f $f.file, (Get-Item $f.file).Length) -ForegroundColor Green
}
if (-not (Test-Path '.\esptool.exe')) { Stop-With "esptool.exe is missing." }
# rollback kit must be complete before we start
$v050 = 'c7c9f047a2a78ad203012206fadd522c938e11f5bc3fc61cda6b68711a3a25b8'
$v040 = 'b181796f1df4b6de47eea32661ee2f5dd1683ab9bcdd3119a67a4d6e61c5eb0b'
if (-not (Test-Path 'ROLLBACK-TO-v050.ps1') -or -not (Test-Path 'fw-v0.5.0\BC050-app.bin')) { Stop-With "the 0.5.0 rollback files (ROLLBACK-TO-v050.ps1, fw-v0.5.0) are missing." }
if ((Get-FileHash 'fw-v0.5.0\BC050-app.bin' -Algorithm SHA256).Hash.ToLower() -ne $v050) { Stop-With "fw-v0.5.0\BC050-app.bin is damaged - rollback would not be possible." }
Write-Host "  Rollback to 0.5.0 available (ROLLBACK-TO-v050.bat, checksum OK)." -ForegroundColor Green
$port = (Get-CimInstance Win32_PnPEntity | Where-Object { $_.Name -match 'CH34|USB-Enhanced|USB Serial|USB Single Serial' -and $_.Name -match '\((COM[0-9]+)\)' } |
         ForEach-Object { if ($_.Name -match '\((COM[0-9]+)\)') { $matches[1] } } | Select-Object -First 1)
if (-not $port) { Stop-With "the Waveshare was not found on any USB port (check the cable)." }
Write-Host "  Waveshare found on $port" -ForegroundColor Green
# 3. full backup of the board as it is now
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$pre = "backup-before-v060-$stamp.bin"
$log = "install-v060-$stamp.txt"
"Install 0.6.0 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') on $port" | Out-File $log -Encoding utf8
Write-Host ""
Write-Host "  Reading a complete backup of the board (16 MB, about 3 minutes): $pre" -ForegroundColor Cyan
& cmd /c ".\esptool.exe --chip esp32s3 -p $port -b 921600 read-flash 0x0 0x1000000 $pre 2>&1" | ForEach-Object { $_ | Out-File $log -Append -Encoding utf8; Write-Host "  $_" }
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $pre)) { Stop-With "the backup could not be read (see $log). Installation not started." }
if ((Get-Item $pre).Length -ne 16777216) { Stop-With "the backup is not 16 MB - installation not started." }
# the app inside the backup at 0x20000: read its version string (esp_app_desc, offset 48) and its exact length by walking
# the image segments, then compare the checksum with the known 0.4.0 / 0.3.0 images. Proves the dump is good AND which
# firmware is on the board.
$fs = [System.IO.File]::OpenRead((Resolve-Path $pre))
$hdr = New-Object byte[] 64; $fs.Seek(0x20000, 'Begin') | Out-Null; $fs.Read($hdr, 0, 64) | Out-Null
if ($hdr[0] -ne 0xE9) { $fs.Close(); Stop-With "no firmware image found at 0x20000 in the backup (first byte 0x{0:X2}). Tell Claude before installing." -f $hdr[0] }
$ver = [System.Text.Encoding]::ASCII.GetString($hdr, 48, 16).Split([char]0)[0]
$segs = $hdr[1]; $pos = 24
for ($i = 0; $i -lt $segs; $i++) { $sh = New-Object byte[] 8; $fs.Seek(0x20000 + $pos, 'Begin') | Out-Null; $fs.Read($sh, 0, 8) | Out-Null; $len = [BitConverter]::ToUInt32($sh, 4); $pos += 8 + $len }
$pos = [int][Math]::Ceiling(($pos + 1) / 16.0) * 16     # checksum byte + padding to 16
if ($hdr[23] -eq 1) { $pos += 32 }                       # appended SHA-256
$img = New-Object byte[] $pos; $fs.Seek(0x20000, 'Begin') | Out-Null; $fs.Read($img, 0, $pos) | Out-Null; $fs.Close()
$sha = [System.Security.Cryptography.SHA256]::Create(); $h = ([BitConverter]::ToString($sha.ComputeHash($img)) -replace '-', '').ToLower()
if ($h -eq $v050) { $found = "0.5.0" } elseif ($h -eq $v040) { $found = "0.4.0" } else { $found = "" }
if (-not $found) { Stop-With "the backup holds firmware '$ver' at 0x20000 with an unknown checksum ($h, $pos bytes). Tell Claude before installing." }
Write-Host "  Backup verified: 16 MB, firmware $found (reports '$ver') + settings + rides saved in $pre" -ForegroundColor Green
"Backup $pre verified: app $found at 0x20000, hash $h, $pos bytes" | Out-File $log -Append -Encoding utf8
Write-Host ""
Write-Host "  This installs 0.6.0 (phone link stays on with the screen off, Quick Settings handle, Wi-Fi page, phone services). Settings and saved rides are kept."
Write-Host "  To go back later: ROLLBACK-TO-v050.bat (0.5.0, keeps data) or RESTORE-BACKUP-BEFORE-v060.bat (exact image)."
Write-Host "  Battery note: the estimate on the screen is an estimate; USB charging with the 500 mAh cell is NOT verified safe (HW-1)." -ForegroundColor Yellow
$ok = Read-Host "  Type YES and press Enter to install, anything else to cancel"
if ($ok -ne 'YES') { Write-Host "  Cancelled - nothing was changed (the backup file is kept)."; Read-Host "  Press Enter to close"; exit 0 }
$eargs = "--chip esp32s3 -p $port -b 460800 write-flash"
foreach ($f in $fw) { $eargs += " $($f.off) $($f.file)" }
& cmd /c ".\esptool.exe $eargs 2>&1" | ForEach-Object { $_ | Out-File $log -Append -Encoding utf8; Write-Host "  $_" }
$code = $LASTEXITCODE
"esptool exit code: $code" | Out-File $log -Append -Encoding utf8
Write-Host ""
if ($code -eq 0) { Write-Host "  INSTALLED. 2 regions written and verified. The board restarts by itself (Home, then follow TEST-v0.6.0.txt)." -ForegroundColor Green }
else { Write-Host "  esptool reported a problem (exit code $code). Run ROLLBACK-TO-v050.bat to go back; send $log to Claude." -ForegroundColor Red }
Write-Host "  Log saved as $log"
Read-Host "  Press Enter to close"
