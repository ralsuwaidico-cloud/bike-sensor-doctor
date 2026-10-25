@echo off
echo BikeComputer firmware 0.7.0 (26 Oct 2026, app 1d4dd740...) - installer launcher (pairing repair + profile sync)
echo Full 16 MB backup first, then YES prompt; settings and rides are kept.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALL-v0.7.0.ps1"
