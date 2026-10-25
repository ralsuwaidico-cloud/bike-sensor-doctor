@echo off
echo BikeComputer firmware 0.6.1 (25 Oct 2026, app d2b0498f...) - installer launcher (touch-wake fix)
echo Full 16 MB backup first, then YES prompt; settings and rides are kept.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALL-v0.6.1.ps1"
