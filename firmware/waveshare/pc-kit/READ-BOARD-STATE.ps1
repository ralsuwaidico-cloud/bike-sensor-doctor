# BikeComputer - READ THE BOARD'S STATE (read-only evidence capture). Run via READ-BOARD-STATE.bat.
#
# WHAT IT DOES (nothing is ever written to the board's flash by this tool):
#   1. finds the board, asks you to type YES;
#   2. puts the board into its USB download mode (the same reset esptool always uses; the firmware does NOT run in between) and
#      reads, in this order: the flash chip ID/size, the partition table, the settings area (NVS), the boot selector (otadata),
#      the crash-record area (coredump, if the table has one) and then a COMPLETE 16 MB backup;
#   3. checks that every small read is byte-identical to the same region inside the 16 MB backup (proves the reads are reliable);
#   4. ONLY IF you type YES a second time: restarts the board normally and records what it prints for 90 seconds. The firmware
#      then runs as it does every time you switch it on (it may restart up to 3 times and end on the RECOVERY screen - that is
#      what it already does; this tool still writes nothing, but the firmware itself updates its own counters and crash record);
#   5. writes SHA256SUMS-state-<time>.txt and tells you which files to send to Claude.
# Why the order matters: the crash record in the 'coredump' area is replaced by the firmware at its next crash, so it is read
# BEFORE the firmware is allowed to run.
# Files (all in this folder): state-<time>-flashid.txt, -pt.bin, -nvs.bin, -otadata.bin, -coredump.bin, -full16MB.bin,
# -bootlog.txt (step 4 only), read-board-state-<time>.txt (this tool's own log).
# NOTE: needs the owner's approval before it is run (it resets the board into download mode).
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
function Stop-With($msg) { Write-Host ""; Write-Host "  STOPPED: $msg" -ForegroundColor Red; Write-Host "  Nothing was written to the board."; Read-Host "  Press Enter to close"; exit 1 }
Write-Host ""
Write-Host "  BIKECOMPUTER - READ BOARD STATE (read-only)" -ForegroundColor Cyan
Write-Host "  --------------------------------------------"
if (-not (Test-Path '.\esptool.exe')) { Stop-With "esptool.exe is missing from this folder." }
$port = (Get-CimInstance Win32_PnPEntity | Where-Object { $_.Name -match 'CH34|USB-Enhanced|USB Serial|USB Single Serial|USB JTAG' -and $_.Name -match '\((COM[0-9]+)\)' } |
         ForEach-Object { if ($_.Name -match '\((COM[0-9]+)\)') { $matches[1] } } | Select-Object -First 1)
if (-not $port) { Stop-With "the board was not found on any USB port (check the cable)." }
Write-Host "  Board found on $port." -ForegroundColor Green
$free = (Get-PSDrive -Name ((Get-Location).Drive.Name)).Free
if ($free -lt 64MB) { Stop-With "less than 64 MB free on this drive - the 16 MB backup would not fit safely." }
Write-Host ""
Write-Host "  This reads the board's memory into files on this PC. Nothing is written to the board."
Write-Host "  The board is switched into download mode for about 4 minutes (the screen may stay dark or frozen meanwhile)."
$ok = Read-Host "  Type YES and press Enter to start"
if ($ok -ne 'YES') { Write-Host "  Cancelled - nothing was done."; Read-Host "  Press Enter to close"; exit 0 }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$base = "state-$stamp"
$log = "read-board-state-$stamp.txt"
"Read board state $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') on $port" | Out-File $log -Encoding utf8
# every read: download-mode reset BEFORE (the app never runs), stay in the loader AFTER (no app start between the reads)
function Esp([string]$what, [string]$cmdArgs) {
  Write-Host "  $what ..." -ForegroundColor Cyan
  "=== $what : esptool $cmdArgs" | Out-File $log -Append -Encoding utf8
  & cmd /c ".\esptool.exe --chip esp32s3 -p $port -b 921600 --before default-reset --after no-reset $cmdArgs 2>&1" | ForEach-Object { $_ | Out-File $log -Append -Encoding utf8 }
  if ($LASTEXITCODE -ne 0) { Stop-With "esptool failed during '$what' (exit $LASTEXITCODE, see $log). Unplug and replug the board; it will start normally." }
}
function Sha([byte[]]$b) { $s = [System.Security.Cryptography.SHA256]::Create(); ([BitConverter]::ToString($s.ComputeHash($b)) -replace '-', '').ToLower() }
function FileSha([string]$p) { (Get-FileHash $p -Algorithm SHA256).Hash.ToLower() }

# 1. flash chip
Esp "Flash chip ID and size" "flash-id"
$fid = Get-Content $log | Select-String -Pattern 'Detected flash size|Manufacturer|Device:|Flash type|Chip type|Features|revision' | ForEach-Object { $_.Line.Trim() }
$fid | Out-File "$base-flashid.txt" -Encoding utf8
Write-Host ("  " + (($fid | Select-String 'Detected flash size') -join ' ')) -ForegroundColor Green

# 2. partition table first (it tells where everything else is)
Esp "Partition table (0x8000, 4 KB)" "read-flash 0x8000 0x1000 $base-pt.bin"
$pt = [System.IO.File]::ReadAllBytes((Resolve-Path "$base-pt.bin"))
$parts = @()
for ($i = 0; $i -lt 96; $i++) {
  $o = $i * 32
  if ($pt[$o] -ne 0xAA -or $pt[$o + 1] -ne 0x50) { break }
  $name = [System.Text.Encoding]::ASCII.GetString($pt, $o + 12, 16).Split([char]0)[0]
  $parts += [pscustomobject]@{ Name = $name; Type = $pt[$o + 2]; Sub = $pt[$o + 3]; Off = [BitConverter]::ToUInt32($pt, $o + 4); Size = [BitConverter]::ToUInt32($pt, $o + 8) }
}
if ($parts.Count -eq 0) { Stop-With "no valid partition table at 0x8000 (first bytes $('{0:X2}{1:X2}' -f $pt[0], $pt[1])). Send $log to Claude." }
"Partition table:" | Out-File $log -Append -Encoding utf8
foreach ($p in $parts) { ("  {0,-10} type {1:X2} sub {2:X2} off 0x{3:X6} size 0x{4:X6}" -f $p.Name, $p.Type, $p.Sub, $p.Off, $p.Size) | Out-File $log -Append -Encoding utf8
  Write-Host ("    {0,-10} 0x{1:X6}  {2,6} KB" -f $p.Name, $p.Off, [int]($p.Size / 1024)) }

# 3. the small evidence regions, each read on its own (compared with the full backup afterwards)
$want = @(
  @{ Tag = 'nvs';      Pick = { param($p) $p.Type -eq 1 -and $p.Sub -eq 2 } },
  @{ Tag = 'otadata';  Pick = { param($p) $p.Type -eq 1 -and $p.Sub -eq 0 } },
  @{ Tag = 'coredump'; Pick = { param($p) $p.Type -eq 1 -and $p.Sub -eq 3 } })
$small = @()
foreach ($w in $want) {
  $p = $parts | Where-Object { & $w.Pick $_ } | Select-Object -First 1
  if (-not $p) { "No '$($w.Tag)' partition in this table (old table has no coredump area)." | Out-File $log -Append -Encoding utf8; Write-Host "  (no $($w.Tag) partition in this table)" -ForegroundColor Yellow; continue }
  $f = "$base-$($w.Tag).bin"
  Esp ("{0} (0x{1:X6}, {2} KB)" -f $w.Tag, $p.Off, [int]($p.Size / 1024)) ("read-flash 0x{0:X} 0x{1:X} {2}" -f $p.Off, $p.Size, $f)
  $small += [pscustomobject]@{ File = $f; Off = $p.Off; Size = $p.Size }
}

# 4. the complete backup (about 3 minutes)
$full = "$base-full16MB.bin"
Esp "Complete 16 MB backup (about 3 minutes)" "read-flash 0x0 0x1000000 $full"
if ((Get-Item $full).Length -ne 16777216) { Stop-With "the full backup is not 16 MB." }

# 5. every small read must equal the same bytes inside the full backup
$fs = [System.IO.File]::OpenRead((Resolve-Path $full))
$allSame = $true
try {
  foreach ($s in (@([pscustomobject]@{ File = "$base-pt.bin"; Off = 0x8000; Size = 0x1000 }) + $small)) {
    $b = New-Object byte[] $s.Size; $fs.Seek($s.Off, 'Begin') | Out-Null; [void]$fs.Read($b, 0, $s.Size)
    $same = (Sha $b) -eq (FileSha $s.File)
    if (-not $same) { $allSame = $false }
    ("compare {0}: {1}" -f $s.File, $(if ($same) { 'identical' } else { 'DIFFERENT' })) | Out-File $log -Append -Encoding utf8
    Write-Host ("  {0,-34} {1}" -f $s.File, $(if ($same) { 'identical in the full backup' } else { 'DIFFERENT from the full backup' })) -ForegroundColor $(if ($same) { 'Green' } else { 'Red' })
  }
} finally { $fs.Close() }
if (-not $allSame) { Write-Host "  Some reads differ - the USB link may be unreliable. Keep all files and tell Claude." -ForegroundColor Red }

# checksums of everything produced so far
$sums = "SHA256SUMS-state-$stamp.txt"
Get-ChildItem "$base-*" | ForEach-Object { "{0}  {1}" -f (FileSha $_.FullName), $_.Name } | Out-File $sums -Encoding ascii
Write-Host ""
Write-Host "  READ DONE. The board's memory is saved; nothing was written to it." -ForegroundColor Green

# 6. optional: let the firmware start and record what it prints
Write-Host ""
Write-Host "  Optional step: restart the board normally and record its start-up messages for 90 seconds."
Write-Host "  The firmware will run as it does whenever you switch it on (it may restart up to 3 times and end on RECOVERY MODE)."
$ok2 = Read-Host "  Type YES to record the start-up, or just press Enter to finish without it"
if ($ok2 -eq 'YES') {
  $bl = "$base-bootlog.txt"
  $sp = New-Object System.IO.Ports.SerialPort $port, 115200, 'None', 8, 'One'
  $sp.ReadTimeout = 300; $sp.DtrEnable = $false; $sp.RtsEnable = $false
  try { $sp.Open() } catch { Write-Host "  Could not open $port for the start-up log. Unplug and replug the board to start it." -ForegroundColor Yellow; Read-Host "  Press Enter to close"; exit 0 }
  "Boot log after read-board-state, $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') on $port" | Out-File $bl -Encoding utf8
  $sp.RtsEnable = $true; Start-Sleep -Milliseconds 150; $sp.RtsEnable = $false   # EN pulse with IO0 high = normal start
  $end = (Get-Date).AddSeconds(90); $n = 0
  try { while ((Get-Date) -lt $end) { try { $line = $sp.ReadLine() } catch [System.TimeoutException] { continue }; $n++; ((Get-Date -Format 'HH:mm:ss.fff') + ' ' + $line.TrimEnd("`r")) | Out-File $bl -Append -Encoding utf8 } }
  finally { $sp.Close() }
  Write-Host "  Start-up recorded: $n lines in $bl" -ForegroundColor Green
  "{0}  {1}" -f (FileSha $bl), $bl | Out-File $sums -Append -Encoding ascii
} else {
  Write-Host "  Finished without starting the firmware. Unplug and replug the board (or press RESET) when you want it to run again."
}
Write-Host ""
Write-Host "  Send these files to Claude: $base-*.bin/.txt, $sums and $log" -ForegroundColor Cyan
Write-Host "  (the 16 MB backup also contains your settings and pairings: keep it private)" -ForegroundColor Yellow
Read-Host "  Press Enter to close"
