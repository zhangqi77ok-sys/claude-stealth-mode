@echo off
chcp 65001 >nul
title Claude 隐身防泄漏健康体检
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-ClaudeStealth.ps1"
pause
