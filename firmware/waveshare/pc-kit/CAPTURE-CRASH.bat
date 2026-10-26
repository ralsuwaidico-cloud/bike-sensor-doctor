@echo off
echo BikeComputer crash capture - one restart, records the board output, saves crash-log-*.txt for Claude.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0CAPTURE-CRASH.ps1"
