@echo off
echo BikeComputer firmware 0.7.2 (26 Oct 2026, app 33b42502...) - installer launcher (power meter data fix + live sensor status)
echo Full 16 MB backup first, then YES prompt; settings, pairings and rides are kept.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALL-v0.7.2.ps1"
