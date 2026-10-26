@echo off
echo BikeComputer firmware 0.7.1 (26 Oct 2026, app 63ace07e...) - installer launcher (0.7.0 + brand-neutral labels)
echo Full 16 MB backup first, then YES prompt; settings and rides are kept.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALL-v0.7.1.ps1"
