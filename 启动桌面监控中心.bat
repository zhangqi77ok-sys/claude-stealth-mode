@echo off
cd /d "%~dp0"

if exist "ClaudeStealthGuardian.exe" goto RUN_ROOT
if exist "desktop\bin\ClaudeStealthGuardian.exe" goto RUN_BIN

echo [!] ClaudeStealthGuardian.exe not found.
pause
exit /b

:RUN_ROOT
start "" "ClaudeStealthGuardian.exe"
exit /b

:RUN_BIN
start "" "desktop\bin\ClaudeStealthGuardian.exe"
exit /b
