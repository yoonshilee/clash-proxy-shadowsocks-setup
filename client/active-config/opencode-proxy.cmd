@echo off
setlocal

REM Generated from server/config/setup.conf(.example) by client/render-client-configs.sh
REM opencode (Bun/runtime variants) does NOT reliably respect WinINET system proxy on Windows.
REM It DOES respect HTTP_PROXY/HTTPS_PROXY env vars.
REM We set them here when Clash mixed port is reachable.
REM This wrapper also tries multiple OpenCode install layouts:
REM 1. OPENCODE_BIN env override
REM 2. sibling opencode.cmd / opencode.exe / opencode
REM 3. opencode on PATH
REM 4. common direct-install cache locations

set "_SELF=%~f0"
set "_SCRIPT_DIR=%~dp0"
set "_USER_HOME=%USERPROFILE%"
set "_OPENCODE_TARGET="
set "_CLASH_RUNNING="
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "if(Get-NetTCPConnection -State Listen -LocalPort 7897 -ErrorAction SilentlyContinue){'yes'}else{'no'}"`) do set "_CLASH_RUNNING=%%i"

if /I "%_CLASH_RUNNING%"=="yes" (
  set "HTTP_PROXY=http://127.0.0.1:7897"
  set "HTTPS_PROXY=http://127.0.0.1:7897"
  set "ALL_PROXY=socks5://127.0.0.1:7898"
  set "NO_PROXY=localhost,127.0.0.1,::1"
  set "http_proxy=http://127.0.0.1:7897"
  set "https_proxy=http://127.0.0.1:7897"
  set "all_proxy=socks5://127.0.0.1:7898"
  set "no_proxy=localhost,127.0.0.1,::1"
  echo [opencode-proxy] Clash detected, proxy enabled
) else (
  echo [opencode-proxy] Clash not detected, starting without proxy
)

if defined OPENCODE_BIN (
  if exist "%OPENCODE_BIN%" (
    set "_OPENCODE_TARGET=%OPENCODE_BIN%"
  ) else (
    echo [opencode-proxy] OPENCODE_BIN is set but missing: %OPENCODE_BIN% 1>&2
    exit /b 1
  )
)

if not defined _OPENCODE_TARGET (
  for %%F in ("%_SCRIPT_DIR%opencode.cmd" "%_SCRIPT_DIR%opencode.exe" "%_SCRIPT_DIR%opencode") do (
    if exist "%%~fF" if /I not "%%~fF"=="%_SELF%" if not defined _OPENCODE_TARGET set "_OPENCODE_TARGET=%%~fF"
  )
)

if not defined _OPENCODE_TARGET (
  for /f "usebackq delims=" %%i in (`where.exe opencode 2^>NUL`) do (
    if /I not "%%~fi"=="%_SELF%" if /I not "%%~nxi"=="opencode-proxy.cmd" if not defined _OPENCODE_TARGET set "_OPENCODE_TARGET=%%~fi"
  )
)

if not defined _OPENCODE_TARGET (
  for %%F in (
    "%_USER_HOME%\.cache\opencode\packages\oh-my-openagent@latest\node_modules\oh-my-openagent-windows-x64\bin\oh-my-opencode.exe"
    "%_USER_HOME%\.cache\opencode\packages\oh-my-openagent@latest\node_modules\oh-my-openagent-windows-x64-baseline\bin\oh-my-opencode.exe"
    "%_USER_HOME%\.cache\opencode\node_modules\.bin\oh-my-opencode.exe"
    "%LOCALAPPDATA%\Programs\opencode\opencode.exe"
    "%LOCALAPPDATA%\Microsoft\WinGet\Links\opencode.exe"
    "%_USER_HOME%\.local\bin\opencode.exe"
    "%_USER_HOME%\.local\share\opencode\bin\opencode.exe"
  ) do (
    if exist "%%~fF" if not defined _OPENCODE_TARGET set "_OPENCODE_TARGET=%%~fF"
  )
)

if not defined _OPENCODE_TARGET (
  echo [opencode-proxy] Could not find an OpenCode executable. 1>&2
  echo [opencode-proxy] Set OPENCODE_BIN to the full path of opencode or oh-my-opencode.exe. 1>&2
  exit /b 1
)

echo [opencode-proxy] Launching: %_OPENCODE_TARGET%
endlocal & "%_OPENCODE_TARGET%" %*
