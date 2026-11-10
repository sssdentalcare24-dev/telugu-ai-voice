@echo off
setlocal EnableExtensions
chcp 65001 >nul
title Telugu AI Voice - PC voice server
color 1F
echo.
echo  ==============================================================
echo    Telugu AI Voice - PC voice server  (unlimited, free)
echo  ==============================================================
echo.

set "HOME_DIR=%LOCALAPPDATA%\TeluguVoiceServer"
if not exist "%HOME_DIR%" mkdir "%HOME_DIR%"
if not exist "%~dp0voice_server.py" goto nofile
copy /y "%~dp0voice_server.py" "%HOME_DIR%\voice_server.py" >nul
cd /d "%HOME_DIR%"
set "PYTHONIOENCODING=utf-8"
set "PYTHONUTF8=1"
set "TELUGU_VOICE_HOME=%HOME_DIR%"
set "VPY=%HOME_DIR%\venv\Scripts\python.exe"

if exist "%HOME_DIR%\installed.ok" goto token

rem ---------------------------------------------------------------
echo  [1/4] Checking for Python 3.11 ...
call :findpy
if defined PYEXE goto havepy
echo        Python 3.11 is not installed. Installing it now - one time only.
where winget >nul 2>nul
if errorlevel 1 goto nowinget
winget install -e --id Python.Python.3.11 --scope user --accept-package-agreements --accept-source-agreements
call :findpy
if defined PYEXE goto havepy
:nowinget
echo.
echo  Python could not be installed automatically.
echo  A download page will open. Install Python 3.11, then double-click this file again.
start "" "https://www.python.org/downloads/release/python-3119/"
goto fail

:havepy
echo        Found: %PYEXE%

rem ---------------------------------------------------------------
echo.
echo  [2/4] Preparing a private folder for the AI ...
if not exist "%VPY%" "%PYEXE%" -m venv "%HOME_DIR%\venv"
if not exist "%VPY%" goto fail
"%VPY%" -m pip install --upgrade pip --quiet
if errorlevel 1 goto fail

rem ---------------------------------------------------------------
echo.
echo  [3/4] Downloading the AI engine. This takes 10-40 minutes the first time.
set "TORCH_INDEX=https://download.pytorch.org/whl/cpu"
nvidia-smi >nul 2>nul
if not errorlevel 1 set "TORCH_INDEX=https://download.pytorch.org/whl/cu126"
if "%TORCH_INDEX%"=="https://download.pytorch.org/whl/cu126" echo        NVIDIA graphics found - voices will be fast.
if not "%TORCH_INDEX%"=="https://download.pytorch.org/whl/cu126" echo        No NVIDIA graphics - voices will be slower, still unlimited.
> "%HOME_DIR%\constraints.txt" echo torch==2.7.1
>> "%HOME_DIR%\constraints.txt" echo torchaudio==2.7.1
"%VPY%" -m pip install torch==2.7.1 torchaudio==2.7.1 --index-url %TORCH_INDEX%
if errorlevel 1 goto fail
"%VPY%" -m pip install -c "%HOME_DIR%\constraints.txt" "https://github.com/AI4Bharat/IndicF5/archive/refs/heads/main.zip" "transformers==4.50.0" fastapi "uvicorn[standard]" python-multipart soundfile
if errorlevel 1 "%VPY%" -m pip install -c "%HOME_DIR%\constraints.txt" "https://github.com/AI4Bharat/IndicF5/archive/refs/heads/master.zip" "transformers==4.50.0" fastapi "uvicorn[standard]" python-multipart soundfile
if errorlevel 1 goto fail
> "%HOME_DIR%\installed.ok" echo ok

rem ---------------------------------------------------------------
:token
if exist "%HOME_DIR%\hf_token.txt" goto run
echo.
echo  [4/4] One time: connect your free Hugging Face account
echo        1. A page opens. Log in, and if you see "Agree and access repository", click it.
echo        2. Paste your token below - the same hf_... token as in the phone app.
echo           No token yet? huggingface.co/settings/tokens - New token - Read - Create.
start "" "https://huggingface.co/ai4bharat/IndicF5"
set "HFTOKEN="
set /p "HFTOKEN=        Paste the token and press Enter: "
if not defined HFTOKEN goto token
> "%HOME_DIR%\hf_token.txt" echo %HFTOKEN%

rem ---------------------------------------------------------------
:run
echo.
echo  Starting the voice server ... the first start downloads the voice model, about 1.4 GB.
"%VPY%" "%HOME_DIR%\voice_server.py"
echo.
echo  The voice server stopped. If you saw an error above, take a photo of this window
echo  and send it to Claude. Press any key to close.
pause >nul
exit /b 0

:nofile
echo  voice_server.py is missing. Keep both files together in one folder - unzip first.
goto fail

:fail
echo.
echo  Something went wrong - see the messages above.
echo  Take a photo of this window and send it to Claude. To start over, run Repair.bat.
pause
exit /b 1

rem --- finds Python 3.11 and sets PYEXE ------------------------------
:findpy
set "PYEXE="
if exist "%LOCALAPPDATA%\Programs\Python\Python311\python.exe" set "PYEXE=%LOCALAPPDATA%\Programs\Python\Python311\python.exe"
if defined PYEXE exit /b 0
if exist "%ProgramFiles%\Python311\python.exe" set "PYEXE=%ProgramFiles%\Python311\python.exe"
if defined PYEXE exit /b 0
where py >nul 2>nul
if errorlevel 1 exit /b 0
for /f "usebackq delims=" %%I in (`py -3.11 -c "import sys; print(sys.executable)" 2^>nul`) do set "PYEXE=%%I"
exit /b 0
