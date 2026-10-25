@echo off
chcp 65001 >nul
title 恢复常规日常工作模式
echo ========================================================
echo        🔄 正在以管理员权限恢复日常工作模式...
echo ========================================================
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0Disable-ClaudeStealth.ps1\"'"
