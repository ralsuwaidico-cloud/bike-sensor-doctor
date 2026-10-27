@echo off
echo BikeComputer firmware 0.7.4-rc1 (app 30f8f37c...) - installer launcher
echo Full 16 MB backup first, then a YES prompt; settings, pairings and rides are kept; the first 90 seconds are checked automatically.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALL-v0.7.4.ps1"
