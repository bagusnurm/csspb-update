@echo off
title Sourcemod Compiler
cd /d "%~dp0"
py compile.py %*
pause