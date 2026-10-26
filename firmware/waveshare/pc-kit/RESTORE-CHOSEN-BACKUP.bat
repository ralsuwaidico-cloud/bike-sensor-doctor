@echo off
echo BikeComputer - restore a backup you choose by number (lists every 16 MB backup with the firmware inside it)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0RESTORE-CHOSEN-BACKUP.ps1"
