@echo off
echo BikeComputer firmware 0.6.0 (rev 3, 25 Oct 2026, app 2cccc1fe...) - installer launcher
echo Full 16 MB backup first, then YES prompt; settings and rides are kept.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALL-v0.6.0.ps1"
