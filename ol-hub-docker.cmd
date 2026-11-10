@echo off
rem OpenLegacy Hub on Docker - Windows launcher.
rem Double-click: opens the OpenLegacy Hub menu in a Git Bash window (correct colours, columns and spinner).
rem In a Command Prompt it takes the same commands as ol-hub-docker.sh, for example:  ol-hub-docker.cmd status
rem It needs Git for Windows (Git Bash). Without it, WSL is used when it is installed.
setlocal
rem Git Bash without its "pseudo console": otherwise Windows programs (docker.exe) can disturb the screen and input
set "MSYS=disable_pcon"
set "HERE=%~dp0"
set "SCRIPT=%HERE:\=/%ol-hub-docker.sh"
set "BASH_EXE="
for %%P in ("%ProgramFiles%\Git\bin\bash.exe" "%ProgramFiles(x86)%\Git\bin\bash.exe" "%LocalAppData%\Programs\Git\bin\bash.exe") do (
  if not defined BASH_EXE if exist "%%~P" set "BASH_EXE=%%~P"
)
if not defined BASH_EXE (
  for /f "delims=" %%G in ('where git.exe 2^>nul') do (
    if not defined BASH_EXE if exist "%%~dpG..\bin\bash.exe" set "BASH_EXE=%%~dpG..\bin\bash.exe"
  )
)
if not defined BASH_EXE goto try_wsl

rem Double-clicked (no command): the menu in Git Bash's own window (mintty)
if not "%~1"=="" goto run_here
for %%B in ("%BASH_EXE%") do set "GIT_ROOT=%%~dpB.."
if not exist "%GIT_ROOT%\usr\bin\mintty.exe" goto run_here
cd /d "%HERE%"
set "MSYSTEM=MINGW64"
set "CHERE_INVOKING=1"
start "" "%GIT_ROOT%\usr\bin\mintty.exe" -t "OpenLegacy Hub" -i "%HERE%assets\ol-hub.ico" -s 110,40 /usr/bin/bash --login -c "./ol-hub-docker.sh menu || { echo; read -r -p 'Press Enter to close this window. '; }"
exit /b 0

:run_here
"%BASH_EXE%" "%SCRIPT%" %*
set "RC=%ERRORLEVEL%"
goto done

:try_wsl
where wsl.exe >nul 2>nul
if errorlevel 1 goto no_bash
pushd "%HERE%"
if "%~1"=="" (wsl.exe bash ./ol-hub-docker.sh menu) else (wsl.exe bash ./ol-hub-docker.sh %*)
set "RC=%ERRORLEVEL%"
popd
goto done

:no_bash
echo.
echo The installer needs Git for Windows (it brings the "Git Bash" terminal):
echo     https://git-scm.com/download/win
echo Install it with the default options, then double-click ol-hub-docker.cmd again.
set "RC=1"

:done
rem Started without a command in this window: keep it open to read the result
if "%~1"=="" (
  echo.
  pause
)
exit /b %RC%
