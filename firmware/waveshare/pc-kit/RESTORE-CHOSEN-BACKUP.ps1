# Bike Computer - restore ONE backup that YOU choose (replaces the old "newest backup" restore scripts: the newest backup may
# now hold the crashing 0.7.2). Lists every 16 MB backup in this folder with the firmware found inside it, you pick its number.
# A backup is a complete image: firmware + partition table + settings + rides AS THEY WERE when it was taken.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
function Stop-With($msg) { Write-Host ""; Write-Host "  STOPPED: $msg" -ForegroundColor Red; Write-Host "  Nothing was changed on the board."; Read-Host "  Press Enter to close"; exit 1 }
$known = @{
  '10c9a7a79085c47a304a52789223368b61d8479c6c13ca71626396941585f306' = '0.7.4-rc3';
  'a495bfde97986f2ba207d50ab92ea8bc1fa75fa45935a5513f23f73ed55ee9d9' = '0.7.4-rc2';
  '30f8f37c7bf67c3d30c2534a5666065fc15321ddbdf535fb7eaa5b509d6ba02e' = '0.7.4-rc1 (never installed)';
  '181b2e5c751108679a2101bfb1c1942b0302fe537527ceaeba207c5256ea4da5' = '0.7.3';
  '735c2699009d5e723a8755975720a570240fed7375ed5a43c06727458d4d6560' = '0.7.3 draft (26 Oct, never released)';
  '33b425022eb12ed7d4b55f343cb76c94ad6677864379112b08352eb36c779a60' = '0.7.2 (the firmware that crash-looped)';
  '63ace07eebd16c6f5c829a0cf67349863cd23ae6a3ff59925bf785678b14ea0f' = '0.7.1';
  '1d4dd740d5a86516b79d16a23df1d5cb6155f3007ff71823dc928d82082a6c67' = '0.7.0';
  'd2b0498f554f5290e31be9bfcf8ad9b0c6630acd641e2d413a64ff7b1039852d' = '0.6.1';
  '2cccc1fe893493194dbbf5471dd4e05f99b0292ca936c66eabd3c9b5e94f9a00' = '0.6.0 rev 3';
  'cdecb1f4b28d6b5aaaed770b7879dfe3e85a520fad29fbc50bb112c70f738139' = '0.6.0 rev 2';
  '7cc2ebe00552d5bbc60017caecf0e081ec59d9562cfb39f58caaa279055d3bbc' = '0.6.0 rev 1';
  'c7c9f047a2a78ad203012206fadd522c938e11f5bc3fc61cda6b68711a3a25b8' = '0.5.0';
  'b181796f1df4b6de47eea32661ee2f5dd1683ab9bcdd3119a67a4d6e61c5eb0b' = '0.4.0' }
function Inspect($path) {
  $fs = [System.IO.File]::OpenRead((Resolve-Path $path))
  try {
    $hdr = New-Object byte[] 64; $fs.Seek(0x20000, 'Begin') | Out-Null; $fs.Read($hdr, 0, 64) | Out-Null
    if ($hdr[0] -ne 0xE9) { return 'no firmware at 0x20000 (factory or unknown)' }
    $ver = [System.Text.Encoding]::ASCII.GetString($hdr, 48, 16).Split([char]0)[0]
    $segs = $hdr[1]; $pos = 24
    for ($i = 0; $i -lt $segs; $i++) { $sh = New-Object byte[] 8; $fs.Seek(0x20000 + $pos, 'Begin') | Out-Null; $fs.Read($sh, 0, 8) | Out-Null; $pos += 8 + [BitConverter]::ToUInt32($sh, 4) }
    $pos = [int][Math]::Ceiling(($pos + 1) / 16.0) * 16; if ($hdr[23] -eq 1) { $pos += 32 }
    if ($pos -gt 0x400000) { return "firmware '$ver' (damaged image)" }
    $img = New-Object byte[] $pos; $fs.Seek(0x20000, 'Begin') | Out-Null; $fs.Read($img, 0, $pos) | Out-Null
    $h = ([BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($img)) -replace '-', '').ToLower()
    if ($known.ContainsKey($h)) { return "firmware $($known[$h])" } else { return "firmware '$ver' (not a kit build)" }
  } finally { $fs.Close() }
}
Write-Host ""; Write-Host "  RESTORE A BACKUP OF YOUR CHOICE" -ForegroundColor Cyan; Write-Host "  -------------------------------"
$files = @(Get-ChildItem -Filter '*.bin' | Where-Object { $_.Length -eq 16777216 } | Sort-Object LastWriteTime)
if (-not $files) { Stop-With "no 16 MB backup (*.bin) found in this folder." }
for ($i = 0; $i -lt $files.Count; $i++) {
  $what = Inspect $files[$i].FullName
  $color = if ($what -match '0\.7\.2') { 'Yellow' } else { 'White' }
  Write-Host ("  [{0}] {1,-44} {2:yyyy-MM-dd HH:mm}  {3}" -f ($i + 1), $files[$i].Name, $files[$i].LastWriteTime, $what) -ForegroundColor $color
}
Write-Host ""
Write-Host "  Writing a backup replaces EVERYTHING on the board with that moment: firmware, partition table, settings, pairings and rides."
Write-Host "  Rides recorded after that backup are lost. A 0.7.2 backup brings the crash loop back." -ForegroundColor Yellow
$pick = Read-Host "  Type the NUMBER of the backup to restore (or press Enter to cancel)"
if (-not $pick) { Write-Host "  Cancelled - nothing was changed."; Read-Host "  Press Enter to close"; exit 0 }
$n = 0; if (-not [int]::TryParse($pick, [ref]$n) -or $n -lt 1 -or $n -gt $files.Count) { Stop-With "'$pick' is not one of the numbers shown." }
$file = $files[$n - 1]
$port = (Get-CimInstance Win32_PnPEntity | Where-Object { $_.Name -match 'CH34|USB-Enhanced|USB Serial|USB Single Serial' -and $_.Name -match '\((COM[0-9]+)\)' } |
         ForEach-Object { if ($_.Name -match '\((COM[0-9]+)\)') { $matches[1] } } | Select-Object -First 1)
if (-not $port) { Stop-With "the Waveshare was not found on any USB port." }
Write-Host "  Chosen: $($file.Name) - $(Inspect $file.FullName). Board on $port."
$ok = Read-Host "  Type RESTORE and press Enter to write it"
if ($ok -ne 'RESTORE') { Write-Host "  Cancelled - nothing was changed."; Read-Host "  Press Enter to close"; exit 0 }
$log = 'restore-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt'
"Restore $($file.Name) on $port $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $log -Encoding utf8
& cmd /c ".\esptool.exe --chip esp32s3 -p $port -b 460800 write-flash 0x0 `"$($file.Name)`" 2>&1" | ForEach-Object { $_ | Out-File $log -Append -Encoding utf8; Write-Host "  $_" }
if ($LASTEXITCODE -eq 0) { Write-Host "  RESTORED and verified. The board restarts by itself." -ForegroundColor Green } else { Write-Host "  esptool reported a problem - send $log to Claude." -ForegroundColor Red }
Read-Host "  Press Enter to close"
