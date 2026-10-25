@echo off
chcp 65001 >nul
title Claude Stealth Guardian

if exist "%~dp0ClaudeStealthGuardian.exe" (
    start "" "%~dp0ClaudeStealthGuardian.exe"
) else if exist "%~dp0desktop\bin\ClaudeStealthGuardian.exe" (
    start "" "%~dp0desktop\bin\ClaudeStealthGuardian.exe"
) else (
    echo [错误] 未找到 ClaudeStealthGuardian.exe，请先编译。
    pause
)
