@echo off
echo BikeComputer firmware 0.7.4-rc2 (app a495bfde...) - installer launcher
echo Full 16 MB backup first, then a YES prompt; settings, pairings and rides are kept; the first 90 seconds of the new firmware are recorded automatically.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALL-v0.7.4-rc2.ps1"
