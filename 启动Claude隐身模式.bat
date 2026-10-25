@echo off
chcp 65001 >nul
title 启动 Claude 终极防检测隐身模式
echo ========================================================
echo        🚀 正在以管理员权限启动 Claude 隐身模式...
echo ========================================================
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0Enable-ClaudeStealth.ps1\"'"
