@echo off
title XDS power meter probe
echo Running the Bluetooth probe with Python 3.14...
py -3.14 "%USERPROFILE%\Documents\xds_probe.py"
if errorlevel 1 py "%USERPROFILE%\Documents\xds_probe.py"
pause
