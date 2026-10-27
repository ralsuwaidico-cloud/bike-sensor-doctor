#!/usr/bin/env python3
"""Generate the 0.7.4 PC-kit scripts with the checksums of pc-kit/fw-v0.7.4/SHA256SUMS.txt (run after copying a new build).
INSTALL-v0.7.4.ps1 is derived from the proven INSTALL-v0.7.3.ps1 (same backup / verify / write / first-boot logic)."""
import os, re, sys

KIT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'pc-kit')
def sums(d):
    out = {}
    for l in open(os.path.join(KIT, d, 'SHA256SUMS.txt')):
        h, f = l.split()
        out[f] = h
    return out

S4, S3, S2 = sums('fw-v0.7.4'), sums('fw-v0.7.3'), sums('fw-v0.7.2')
APP4, APP3, APP2 = S4['BC074-app.bin'], S3['BC073-app.bin'], S2['BC072-app.bin']
VER = '0.7.4-rc1'

src = open(os.path.join(KIT, 'INSTALL-v0.7.3.ps1'), encoding='utf-8-sig').read()
head_end = src.index('$ErrorActionPreference')
head = f'''# Bike Computer - install firmware {VER} (crash fix: Bluetooth start-up never aborts or loops; real storage categories;
# crash / start-up records kept in NVS independent of the file system). Run via INSTALL-v0.7.4.bat. App SHA-256 {APP4[:8]}...
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
'''
s = head + src[head_end:]
rep = [
    ('INSTALL BIKE COMPUTER FIRMWARE 0.7.3 (stability + crash records + recovery screen)', f'INSTALL BIKE COMPUTER FIRMWARE {VER} (crash fix + crash records + storage check)'),
    ('---------------------------------------------------------------------------------', '-----------------------------------------------------------------------------'),
    ("'fw-v0.7.3\\BC073-app.bin';      sha = '181b2e5c751108679a2101bfb1c1942b0302fe537527ceaeba207c5256ea4da5'", f"'fw-v0.7.4\\BC074-app.bin';      sha = '{APP4}'"),
    ("'fw-v0.7.3\\BC073-otadata.bin';  sha = '7d2c7ac4888bfd75cd5f56e8d61f69595121183afc81556c876732fd3782c62f'", f"'fw-v0.7.4\\BC074-otadata.bin';  sha = '{S4['BC074-otadata.bin']}'"),
    ("'fw-v0.7.3\\BC073-partitions.bin'; sha = 'f08892b0911b15439bc0552bf1c6190067c3fe62378553cc55156b783caa7d37'", f"'fw-v0.7.4\\BC074-partitions.bin'; sha = '{S4['BC074-partitions.bin']}'"),
    ("'fw-v0.7.3\\BC073-bootloader.bin'; sha = '6f379e6765dd7eb087415739b4e02a7dae4b44566074e91e12425054291562b9'", f"'fw-v0.7.4\\BC074-bootloader.bin'; sha = '{S4['BC074-bootloader.bin']}'"),
    ("$known = [ordered]@{\n", f"$known = [ordered]@{{\n  '{APP4}' = '{VER}';\n"),
    ("# rollback kit must be complete before we start\nif (-not (Test-Path 'ROLLBACK-TO-v071.ps1') -or -not (Test-Path 'fw-v0.7.1\\BC071-app.bin')) { Stop-With \"the 0.7.1 rollback files (ROLLBACK-TO-v071.ps1, fw-v0.7.1) are missing.\" }\nif ((Get-FileHash 'fw-v0.7.1\\BC071-app.bin' -Algorithm SHA256).Hash.ToLower() -ne '63ace07eebd16c6f5c829a0cf67349863cd23ae6a3ff59925bf785678b14ea0f') { Stop-With \"fw-v0.7.1\\BC071-app.bin is damaged - rollback would not be possible.\" }",
     f"# rollback kit must be complete before we start\nif (-not (Test-Path 'ROLLBACK-TO-v073.ps1') -or -not (Test-Path 'fw-v0.7.3\\BC073-app.bin')) {{ Stop-With \"the 0.7.3 rollback files (ROLLBACK-TO-v073.ps1, fw-v0.7.3) are missing.\" }}\nif ((Get-FileHash 'fw-v0.7.3\\BC073-app.bin' -Algorithm SHA256).Hash.ToLower() -ne '{APP3}') {{ Stop-With \"fw-v0.7.3\\BC073-app.bin is damaged - rollback would not be possible.\" }}\nif (-not (Test-Path 'ROLLBACK-TO-v072.ps1') -or -not (Test-Path 'fw-v0.7.2\\BC072-app.bin')) {{ Stop-With \"the 0.7.2 rollback files (ROLLBACK-TO-v072.ps1, fw-v0.7.2) are missing.\" }}\nif ((Get-FileHash 'fw-v0.7.2\\BC072-app.bin' -Algorithm SHA256).Hash.ToLower() -ne '{APP2}') {{ Stop-With \"fw-v0.7.2\\BC072-app.bin is damaged - rollback would not be possible.\" }}"),
    ('Write-Host "  Rollback to 0.7.1 and backup restore available."', 'Write-Host "  Rollback to 0.7.3 / 0.7.2 and backup restore available."'),
    ('$pre = "backup-before-v073-$stamp.bin"', '$pre = "backup-before-v074-$stamp.bin"'),
    ('$log = "install-v073-$stamp.txt"', '$log = "install-v074-$stamp.txt"'),
    ('"Install 0.7.3 $(Get-Date', f'"Install {VER} $(Get-Date'),
    ('Write-Host "  0.7.3 moves all Bluetooth work onto one task (0.7.2 raced it), keeps a record of any crash on the board, shows a RECOVERY"\nWrite-Host "  screen instead of SAFE MODE, and can send its reports to Cyclift. Settings, pairings, phone bonds and rides are kept."',
     f'Write-Host "  {VER} fixes the 0.7.3 start-up crash: if Bluetooth cannot start, the board keeps running and says why (no crash loop)."\nWrite-Host "  It shows the real storage problem and keeps start-up records in the settings area. Settings, pairings and rides are kept."'),
    ("$boot = \"first-boot-v073-$stamp.txt\"", "$boot = \"first-boot-v074-$stamp.txt\""),
    ('Recording the first 60 seconds of the new firmware', 'Recording the first 90 seconds of the new firmware'),
    ('"First boot after installing 0.7.3 on $port', f'"First boot after installing {VER} on $port'),
    ('$end = (Get-Date).AddSeconds(60)', '$end = (Get-Date).AddSeconds(90); $btFail = $false; $btOk = $false; $storageCat = \'\''),
    ("    if ($line -match 'STAGE stable for 20 s') { $stable = $true }",
     "    if ($line -match 'STAGE stable for 20 s') { $stable = $true }\n    if ($line -match 'Bluetooth unavailable') { $btFail = $true }\n    if ($line -match 'Bluetooth stack up') { $btOk = $true }\n    if ($line -match 'storage: ([A-Za-z ]+):') { $storageCat = $matches[1] }"),
    ('"--- $lines lines; version $version; mode $mode; crashed $crashed; stable $stable; recovery $recovery ---"',
     '"--- $lines lines; version $version; mode $mode; crashed $crashed; stable $stable; recovery $recovery; bluetooth_ok $btOk; bluetooth_failed $btFail; storage $storageCat ---"'),
    ("elseif ($stable -and $version -eq '0.7.3') { Write-Host \"  RESULT: BOOTED OK - firmware 0.7.3 ran 20 s without a crash ($lines log lines). Next: TEST-v0.7.3.txt\" -ForegroundColor Green }",
     f"elseif ($stable -and $version -eq '{VER}') {{ Write-Host \"  RESULT: BOOTED OK - firmware {VER} ran 20 s without a crash ($lines log lines). Bluetooth: $(if ($btOk) {{ 'started' }} elseif ($btFail) {{ 'UNAVAILABLE (the board keeps running; send the log)' }} else {{ 'unknown' }}). Storage: $(if ($storageCat) {{ $storageCat }} else {{ 'see log' }}). Next: TEST-v0.7.4.txt\" -ForegroundColor Green }}"),
]
for a, b in rep:
    if a not in s:
        sys.exit('pattern not found: ' + a[:80])
    s = s.replace(a, b)
assert '0.7.3' not in s.split("$known")[0].replace('0.7.3 table', '').replace('0.7.3 partition', '').replace('ROLLBACK-TO-v073', '').replace('0.7.3,', '').replace('0.7.3 /', '').replace('documented change 0.7.3', ''), 'stray 0.7.3 in header/files'
open(os.path.join(KIT, 'INSTALL-v0.7.4.ps1'), 'w', encoding='utf-8-sig').write(s)
open(os.path.join(KIT, 'INSTALL-v0.7.4.bat'), 'w', newline='\r\n').write(
    f'@echo off\necho BikeComputer firmware {VER} (app {APP4[:8]}...) - installer launcher\n'
    'echo Full 16 MB backup first, then a YES prompt; settings, pairings and rides are kept; the first 90 seconds are checked automatically.\n'
    'powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALL-v0.7.4.ps1"\n')

rb = open(os.path.join(KIT, 'ROLLBACK-TO-v071.ps1'), encoding='utf-8-sig').read()
for ver, d, pre, S, extra in (('0.7.3', 'fw-v0.7.3', 'BC073', S3, ''), ('0.7.2', 'fw-v0.7.2', 'BC072', S2,
        ' 0.7.2 is the firmware that crash-looped on 26 Oct - use it only if Claude asks.')):
    t = rb.replace('0.7.1', ver).replace('fw-v0.7.1', d).replace('BC071', pre).replace('v071', 'v0' + ver.replace('.', '')[1:])
    t = t.replace("sha = '7d2c7ac4888bfd75cd5f56e8d61f69595121183afc81556c876732fd3782c62f'", f"sha = '{S[pre + '-otadata.bin']}'")
    t = t.replace("sha = '63ace07eebd16c6f5c829a0cf67349863cd23ae6a3ff59925bf785678b14ea0f'", f"sha = '{S[pre + '-app.bin']}'")
    t = t.replace('# Writes only the OTA selector', f'# The partition table is left as it is (both table versions work with {ver}).{extra}\n# Writes only the OTA selector')
    name = 'ROLLBACK-TO-v0' + ver.replace('.', '')[1:]
    open(os.path.join(KIT, name + '.ps1'), 'w', encoding='utf-8-sig').write(t)
    open(os.path.join(KIT, name + '.bat'), 'w', newline='\r\n').write(f'@echo off\npowershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0{name}.ps1"\n')

r = open(os.path.join(KIT, 'RESTORE-CHOSEN-BACKUP.ps1'), encoding='utf-8-sig').read()
if APP4 not in r:
    r = re.sub(r"\$known = @\{\n", f"$known = @{{\n  '{APP4}' = '{VER}';\n", r, count=1)
open(os.path.join(KIT, 'RESTORE-CHOSEN-BACKUP.ps1'), 'w', encoding='utf-8-sig').write(r)
print('kit scripts generated for app', APP4)
