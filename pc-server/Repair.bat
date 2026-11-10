@echo off
chcp 65001 >nul
title Telugu AI Voice - repair
echo This removes the installed AI engine and the saved token so the next start installs everything again.
echo Your phone and its saved voices are not affected.
pause
set "HOME_DIR=%LOCALAPPDATA%\TeluguVoiceServer"
if exist "%HOME_DIR%\installed.ok" del /q "%HOME_DIR%\installed.ok"
if exist "%HOME_DIR%\hf_token.txt" del /q "%HOME_DIR%\hf_token.txt"
if exist "%HOME_DIR%\venv" rmdir /s /q "%HOME_DIR%\venv"
echo Done. Now double-click "Telugu-Voice-PC-Server.bat" again.
pause
