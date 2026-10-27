# Bike Computer - install firmware 0.7.4-rc1 (crash fix: Bluetooth start-up never aborts or loops; real storage categories;
# crash / start-up records kept in NVS independent of the file system). Run via INSTALL-v0.7.4.bat. App SHA-256 30f8f37c...
# Safety, in this order:
#   1. factory backup present (16 MB); every 0.7.4 file matches its SHA-256; the rollback files (0.7.3, 0.7.2) are present and intact;
#   2. a COMPLETE 16 MB backup of the board as it is now (firmware + settings + pairings + rides) is read to
#      backup-before-v074-<time>.bin and checked: size, a known firmware at 0x20000 and a known partition table at 0x8000 -
#      so the backup is proven good BEFORE anything is written;
#   3. you type YES;
#   4. written: ONLY the app (0x20000) and the OTA selector (0xf000) - and, only if the board still has the pre-0.7.3 table,
#      the 0.7.3 partition table (0x8000, the same documented change 0.7.3 made: 64 KB of the unused second app slot become
#      the crash-record area). The bootloader, settings / pairings (NVS 0x9000) and the storage area (0x820000-0xFFFFFF) are
#      never written and never erased. Nothing is erased except the sectors the new app and OTA selector are written into;
#   5. the board restarts and this window records its first 90 seconds and tells you "BOOTED OK" or what it saw.
# Go back: ROLLBACK-TO-v073.bat / ROLLBACK-TO-v072.bat (keep data) or RESTORE-CHOSEN-BACKUP.bat (pick any backup by number).
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
function Stop-With($msg) { Write-Host ""; Write-Host "  STOPPED: $msg" -ForegroundColor Red; Write-Host "  Nothing was changed on the board."; Read-Host "  Press Enter to close"; exit 1 }
Write-Host ""
Write-Host "  INSTALL BIKE COMPUTER FIRMWARE 0.7.4-rc1 (crash fix + crash records + storage check)" -ForegroundColor Cyan
Write-Host "  -----------------------------------------------------------------------------"
$bk = Join-Path $PSScriptRoot 'factory_backup_16MB.bin'
if (-not (Test-Path $bk)) { Stop-With "factory_backup_16MB.bin is not in this folder." }
if ((Get-Item $bk).Length -ne 16777216) { Stop-With "factory_backup_16MB.bin is not 16 MB - the backup looks damaged." }
Write-Host "  Factory backup present (16 MB) - kept untouched." -ForegroundColor Green
$app = @{ off = '0x20000'; file = 'fw-v0.7.4\BC074-app.bin';      sha = '30f8f37c7bf67c3d30c2534a5666065fc15321ddbdf535fb7eaa5b509d6ba02e' }
$ota = @{ off = '0xf000';  file = 'fw-v0.7.4\BC074-otadata.bin';  sha = '7d2c7ac4888bfd75cd5f56e8d61f69595121183afc81556c876732fd3782c62f' }
$pt  = @{ off = '0x8000';  file = 'fw-v0.7.4\BC074-partitions.bin'; sha = 'f08892b0911b15439bc0552bf1c6190067c3fe62378553cc55156b783caa7d37' }
$bl  = @{ file = 'fw-v0.7.4\BC074-bootloader.bin'; sha = 'e56cefbad47250ede64b5a1205c9391a1d08cf0106f1656c258f70b71b80b5ed' }   # verified only, never written
foreach ($f in @($app, $ota, $pt, $bl)) {
  if (-not (Test-Path $f.file)) { Stop-With "$($f.file) is missing." }
  $h = (Get-FileHash $f.file -Algorithm SHA256).Hash.ToLower()
  if ($h -ne $f.sha) { Stop-With "$($f.file) does not match its checksum (download damaged?)." }
  Write-Host ("  OK  {0,-34} {1,9} bytes  checksum matches" -f $f.file, (Get-Item $f.file).Length) -ForegroundColor Green
}
if (-not (Test-Path '.\esptool.exe')) { Stop-With "esptool.exe is missing." }
# known firmware images (app at 0x20000) and partition tables (0x8000, 3072 bytes)
$known = [ordered]@{
  '30f8f37c7bf67c3d30c2534a5666065fc15321ddbdf535fb7eaa5b509d6ba02e' = '0.7.4-rc1';
  '181b2e5c751108679a2101bfb1c1942b0302fe537527ceaeba207c5256ea4da5' = '0.7.3';
  '735c2699009d5e723a8755975720a570240fed7375ed5a43c06727458d4d6560' = '0.7.3 draft (26 Oct, never released)';
  '33b425022eb12ed7d4b55f343cb76c94ad6677864379112b08352eb36c779a60' = '0.7.2';
  '63ace07eebd16c6f5c829a0cf67349863cd23ae6a3ff59925bf785678b14ea0f' = '0.7.1';
  '1d4dd740d5a86516b79d16a23df1d5cb6155f3007ff71823dc928d82082a6c67' = '0.7.0';
  'd2b0498f554f5290e31be9bfcf8ad9b0c6630acd641e2d413a64ff7b1039852d' = '0.6.1';
  '2cccc1fe893493194dbbf5471dd4e05f99b0292ca936c66eabd3c9b5e94f9a00' = '0.6.0 rev 3';
  'cdecb1f4b28d6b5aaaed770b7879dfe3e85a520fad29fbc50bb112c70f738139' = '0.6.0 rev 2';
  '7cc2ebe00552d5bbc60017caecf0e081ec59d9562cfb39f58caaa279055d3bbc' = '0.6.0 rev 1';
  'c7c9f047a2a78ad203012206fadd522c938e11f5bc3fc61cda6b68711a3a25b8' = '0.5.0';
  'b181796f1df4b6de47eea32661ee2f5dd1683ab9bcdd3119a67a4d6e61c5eb0b' = '0.4.0' }
$ptOld = '812e16cc1b709a18f7d791de3b2d2f7abec36831edf2ba058e205fb42d603fe6'   # 0.4.0 .. 0.7.2 table
$ptNew = $pt.sha
# rollback kit must be complete before we start
if (-not (Test-Path 'ROLLBACK-TO-v073.ps1') -or -not (Test-Path 'fw-v0.7.3\BC073-app.bin')) { Stop-With "the 0.7.3 rollback files (ROLLBACK-TO-v073.ps1, fw-v0.7.3) are missing." }
if ((Get-FileHash 'fw-v0.7.3\BC073-app.bin' -Algorithm SHA256).Hash.ToLower() -ne '181b2e5c751108679a2101bfb1c1942b0302fe537527ceaeba207c5256ea4da5') { Stop-With "fw-v0.7.3\BC073-app.bin is damaged - rollback would not be possible." }
if (-not (Test-Path 'ROLLBACK-TO-v072.ps1') -or -not (Test-Path 'fw-v0.7.2\BC072-app.bin')) { Stop-With "the 0.7.2 rollback files (ROLLBACK-TO-v072.ps1, fw-v0.7.2) are missing." }
if ((Get-FileHash 'fw-v0.7.2\BC072-app.bin' -Algorithm SHA256).Hash.ToLower() -ne '33b425022eb12ed7d4b55f343cb76c94ad6677864379112b08352eb36c779a60') { Stop-With "fw-v0.7.2\BC072-app.bin is damaged - rollback would not be possible." }
if (-not (Test-Path 'RESTORE-CHOSEN-BACKUP.ps1')) { Stop-With "RESTORE-CHOSEN-BACKUP.ps1 is missing." }
Write-Host "  Rollback to 0.7.3 / 0.7.2 and backup restore available." -ForegroundColor Green
$port = (Get-CimInstance Win32_PnPEntity | Where-Object { $_.Name -match 'CH34|USB-Enhanced|USB Serial|USB Single Serial' -and $_.Name -match '\((COM[0-9]+)\)' } |
         ForEach-Object { if ($_.Name -match '\((COM[0-9]+)\)') { $matches[1] } } | Select-Object -First 1)
if (-not $port) { Stop-With "the Waveshare was not found on any USB port (check the cable)." }
Write-Host "  Waveshare found on $port" -ForegroundColor Green
# full backup of the board as it is now
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$pre = "backup-before-v074-$stamp.bin"
$log = "install-v074-$stamp.txt"
"Install 0.7.4-rc1 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') on $port" | Out-File $log -Encoding utf8
Write-Host ""
Write-Host "  Reading a complete backup of the board (16 MB, about 3 minutes): $pre" -ForegroundColor Cyan
& cmd /c ".\esptool.exe --chip esp32s3 -p $port -b 921600 read-flash 0x0 0x1000000 $pre 2>&1" | ForEach-Object { $_ | Out-File $log -Append -Encoding utf8; Write-Host "  $_" }
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $pre)) { Stop-With "the backup could not be read (see $log). Installation not started." }
if ((Get-Item $pre).Length -ne 16777216) { Stop-With "the backup is not 16 MB - installation not started." }
$fs = [System.IO.File]::OpenRead((Resolve-Path $pre))
try {
  # app at 0x20000: walk the image segments to its exact length, hash it
  $hdr = New-Object byte[] 64; $fs.Seek(0x20000, 'Begin') | Out-Null; $fs.Read($hdr, 0, 64) | Out-Null
  if ($hdr[0] -ne 0xE9) { Stop-With ("no firmware image found at 0x20000 in the backup (first byte 0x{0:X2}). Tell Claude before installing." -f $hdr[0]) }
  $ver = [System.Text.Encoding]::ASCII.GetString($hdr, 48, 16).Split([char]0)[0]
  $segs = $hdr[1]; $pos = 24
  for ($i = 0; $i -lt $segs; $i++) { $sh = New-Object byte[] 8; $fs.Seek(0x20000 + $pos, 'Begin') | Out-Null; $fs.Read($sh, 0, 8) | Out-Null; $pos += 8 + [BitConverter]::ToUInt32($sh, 4) }
  $pos = [int][Math]::Ceiling(($pos + 1) / 16.0) * 16
  if ($hdr[23] -eq 1) { $pos += 32 }
  $img = New-Object byte[] $pos; $fs.Seek(0x20000, 'Begin') | Out-Null; $fs.Read($img, 0, $pos) | Out-Null
  $sha = [System.Security.Cryptography.SHA256]::Create(); $h = ([BitConverter]::ToString($sha.ComputeHash($img)) -replace '-', '').ToLower()
  # partition table at 0x8000 (3072 bytes)
  $tb = New-Object byte[] 3072; $fs.Seek(0x8000, 'Begin') | Out-Null; $fs.Read($tb, 0, 3072) | Out-Null
  $ph = ([BitConverter]::ToString($sha.ComputeHash($tb)) -replace '-', '').ToLower()
} finally { $fs.Close() }
$found = $known[$h]
if (-not $found) { Stop-With "the backup holds firmware '$ver' at 0x20000 with an unknown checksum ($h, $pos bytes). Tell Claude before installing." }
if ($ph -eq $ptOld) { $writeTable = $true; $tbl = 'old (0.4.0-0.7.2) table' } elseif ($ph -eq $ptNew) { $writeTable = $false; $tbl = '0.7.3 table already' } else { Stop-With "the partition table in the backup is not a known one ($ph). Tell Claude before installing." }
Write-Host "  Backup verified: 16 MB, firmware $found (reports '$ver'), $tbl, settings + rides saved in $pre" -ForegroundColor Green
"Backup $pre verified: app $found hash $h ($pos bytes); partition table $ph ($tbl)" | Out-File $log -Append -Encoding utf8
Write-Host ""
Write-Host "  0.7.4-rc1 fixes the 0.7.3 start-up crash: if Bluetooth cannot start, the board keeps running and says why (no crash loop)."
Write-Host "  It shows the real storage problem and keeps start-up records in the settings area. Settings, pairings and rides are kept."
if ($writeTable) { Write-Host "  Partition table: 64 KB of the unused second app slot become a crash-record area; settings, pairings, rides and the running slot do not move." -ForegroundColor Yellow }
Write-Host "  Battery note: the estimate on the screen is an estimate; USB charging with the 500 mAh cell is NOT verified safe (HW-1)." -ForegroundColor Yellow
$ok = Read-Host "  Type YES and press Enter to install, anything else to cancel"
if ($ok -ne 'YES') { Write-Host "  Cancelled - nothing was changed (the backup file is kept)."; Read-Host "  Press Enter to close"; exit 0 }
$eargs = "--chip esp32s3 -p $port -b 460800 write-flash"
if ($writeTable) { $eargs += " $($pt.off) $($pt.file)" }
$eargs += " $($ota.off) $($ota.file) $($app.off) $($app.file)"
& cmd /c ".\esptool.exe $eargs 2>&1" | ForEach-Object { $_ | Out-File $log -Append -Encoding utf8; Write-Host "  $_" }
$code = $LASTEXITCODE
"esptool exit code: $code" | Out-File $log -Append -Encoding utf8
if ($code -ne 0) { Write-Host "  esptool reported a problem (exit code $code). Run RESTORE-CHOSEN-BACKUP.bat and pick $pre; send $log to Claude." -ForegroundColor Red; Read-Host "  Press Enter to close"; exit 1 }
Write-Host ("  INSTALLED. {0} regions written and verified." -f $(if ($writeTable) { 3 } else { 2 })) -ForegroundColor Green
# ---- first 60 seconds after the restart: recorded and judged here, no second tool needed
$boot = "first-boot-v074-$stamp.txt"
Write-Host ""
Write-Host "  Recording the first 90 seconds of the new firmware (keep the board connected) -> $boot" -ForegroundColor Cyan
Start-Sleep -Milliseconds 300
$sp = New-Object System.IO.Ports.SerialPort $port, 115200, 'None', 8, 'One'
$sp.ReadTimeout = 300; $sp.DtrEnable = $false; $sp.RtsEnable = $false
$crashed = $false; $stable = $false; $version = ''; $mode = ''; $lines = 0; $recovery = $false
try { $sp.Open() } catch { Write-Host "  Could not open $port for the boot log (another program?). The firmware is installed." -ForegroundColor Yellow; Read-Host "  Press Enter to close"; exit 0 }
"First boot after installing 0.7.4-rc1 on $port, $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $boot -Encoding utf8
# one reset: EN low with IO0 high = a normal start (esptool already reset the board; this makes sure the start is recorded)
$sp.RtsEnable = $true; Start-Sleep -Milliseconds 150; $sp.RtsEnable = $false
$end = (Get-Date).AddSeconds(90); $btFail = $false; $btOk = $false; $storageCat = ''
try {
  while ((Get-Date) -lt $end) {
    try { $line = $sp.ReadLine() } catch [System.TimeoutException] { continue }
    $lines++; ((Get-Date -Format 'HH:mm:ss.fff') + ' ' + $line.TrimEnd("`r")) | Out-File $boot -Append -Encoding utf8
    if ($line -match 'Bike Computer firmware (\S+)') { $version = $matches[1] }
    if ($line -match 'boot mode (\w+)') { $mode = $matches[1] }
    if ($line -match 'Guru Meditation|abort\(\) was called|Stack canary|stack overflow|LoadProhibited|StoreProhibited|InstrFetchProhibited|IllegalInstruction|Interrupt wdt') { $crashed = $true; Write-Host "  CRASH seen in the log." -ForegroundColor Red }
    if ($line -match 'reset reason: (crash|interrupt watchdog|task watchdog|watchdog)') { $crashed = $true; Write-Host "  The board reports a crash reset." -ForegroundColor Red }
    if ($line -match 'RECOVERY MODE') { $recovery = $true }
    if ($line -match 'STAGE stable for 20 s') { $stable = $true }
    if ($line -match 'Bluetooth unavailable') { $btFail = $true }
    if ($line -match 'Bluetooth stack up') { $btOk = $true }
    if ($line -match 'storage: ([A-Za-z ]+):') { $storageCat = $matches[1] }
  }
} finally { $sp.Close() }
"--- $lines lines; version $version; mode $mode; crashed $crashed; stable $stable; recovery $recovery; bluetooth_ok $btOk; bluetooth_failed $btFail; storage $storageCat ---" | Out-File $boot -Append -Encoding utf8
Write-Host ""
if ($crashed) { Write-Host "  RESULT: CRASHED during the first minute. The board keeps a crash report; send $boot and $log to Claude." -ForegroundColor Red }
elseif ($recovery) { Write-Host "  RESULT: the board is in RECOVERY MODE. Send $boot to Claude before pressing anything." -ForegroundColor Yellow }
elseif ($stable -and $version -eq '0.7.4-rc1') { Write-Host "  RESULT: BOOTED OK - firmware 0.7.4-rc1 ran 20 s without a crash ($lines log lines). Bluetooth: $(if ($btOk) { 'started' } elseif ($btFail) { 'UNAVAILABLE (the board keeps running; send the log)' } else { 'unknown' }). Storage: $(if ($storageCat) { $storageCat } else { 'see log' }). Next: TEST-v0.7.4.txt" -ForegroundColor Green }
elseif ($lines -eq 0) { Write-Host "  RESULT: the board printed nothing (charge-only cable or port busy). Check the screen: it should show Home." -ForegroundColor Yellow }
else { Write-Host "  RESULT: started (version '$version') but did not report 20 s stable within the minute. Send $boot to Claude." -ForegroundColor Yellow }
Write-Host "  Logs: $log, $boot"
Read-Host "  Press Enter to close"
