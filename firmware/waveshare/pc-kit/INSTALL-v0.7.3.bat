@echo off
echo BikeComputer firmware 0.7.3 (27 Oct 2026, app 181b2e5c...) - installer launcher (stability + crash records + recovery screen)
echo Full 16 MB backup first, then YES prompt; settings, pairings and rides are kept; the first minute after the install is checked automatically.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALL-v0.7.3.ps1"
