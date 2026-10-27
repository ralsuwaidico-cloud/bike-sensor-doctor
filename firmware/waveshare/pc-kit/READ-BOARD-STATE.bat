@echo off
echo BikeComputer - read the board's state (read-only: settings, crash record, storage, full 16 MB backup). Nothing is written to the board.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0READ-BOARD-STATE.ps1"
