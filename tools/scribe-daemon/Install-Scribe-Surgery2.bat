@echo off
REM ============================================================
REM  Ivory Chair-side Scribe - INSTALLER for the Surgery 2 PC
REM  ----------------------------------------------------------
REM  1. Plug in the Lark M2 receiver (USB) and switch on the mic.
REM  2. DOUBLE-CLICK this file.
REM  That's it. It installs everything and starts the scribe.
REM ============================================================
cd /d "%~dp0"
echo Starting the Ivory Scribe installer for Surgery 2...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-surgery2.ps1"
echo.
echo ============================================================
echo  If you saw "listening on 'Surgery 2'" above - it is WORKING.
echo  You can close this window; it starts by itself next login.
echo  If you saw RED text, photograph it and send it to Paul.
echo ============================================================
pause
