@echo off
chcp 65001 >nul
cd /d "%~dp0"
title WorkBuddy2API Gateway control

set "BRANCH=unknown"
for /f "delims=" %%b in ('git branch --show-current 2^>nul') do set "BRANCH=%%b"

:MENU
cls
set RUNNING=no
%SystemRoot%\System32\tasklist.exe /FI "IMAGENAME eq wb2api.exe" 2>nul | %SystemRoot%\System32\find.exe /I "wb2api.exe" >nul && set RUNNING=yes

echo ==============================================
echo   WorkBuddy2API Gateway control
echo ==============================================
echo   Branch: %BRANCH%
echo   Status: %RUNNING%
if not exist "wb2api.exe" echo   [WARN] wb2api.exe not found - use [4] to build it.
echo.
echo   [1] Start   (background, silent - safe to close)
echo   [2] Stop
echo   [3] Restart (stop, apply new build if any, start)
echo   [4] Rebuild from current branch and restart
echo   [0] Quit
echo ==============================================
set "choice="
set /p "choice=Type 1, 2, 3, 4 or 0, then press Enter: "

if "%choice%"=="1" goto START
if "%choice%"=="2" goto STOP
if "%choice%"=="3" goto RESTART
if "%choice%"=="4" goto REBUILD
if "%choice%"=="0" exit /b 0
goto MENU

:START
echo.
if /I "%RUNNING%"=="yes" (
    echo [SKIP] Gateway is already running. Use [3] to restart it.
    goto WAITCLOSE
)
goto LAUNCH

:RESTART
echo.
if /I "%RUNNING%"=="no" (
    echo [INFO] Gateway is not running. Starting it now ...
    goto LAUNCH
)
echo Restarting WorkBuddy2API gateway ...
%SystemRoot%\System32\taskkill.exe /IM wb2api.exe /F >nul 2>&1
set /a tries=0
:WAITDEAD
%SystemRoot%\System32\tasklist.exe /FI "IMAGENAME eq wb2api.exe" 2>nul | %SystemRoot%\System32\find.exe /I "wb2api.exe" >nul
if errorlevel 1 goto STOPPED
set /a tries+=1
if %tries% GEQ 10 goto WAITTIMEOUT
%SystemRoot%\System32\ping.exe -n 2 127.0.0.1 >nul
goto WAITDEAD
:STOPPED
echo [OK] Stopped.
goto LAUNCH
:WAITTIMEOUT
echo [WARN] Process still listed after ~10s. Trying to start anyway ...
goto LAUNCH

:REBUILD
echo.
echo Rebuilding from branch: %BRANCH%
call :KILLGATE
set "GO="
if exist "D:\tools\go\bin\go.exe" set "GO=D:\tools\go\bin\go.exe"
if not defined GO if exist "%ProgramFiles%\Go\bin\go.exe" set "GO=%ProgramFiles%\Go\bin\go.exe"
if not defined GO if exist "%LOCALAPPDATA%\Programs\Go\bin\go.exe" set "GO=%LOCALAPPDATA%\Programs\Go\bin\go.exe"
if not defined GO set "GO=go"
"%GO%" version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Go toolchain not found. Edit GO in this script to the full path of go.exe.
    pause
    goto MENU
)
if exist "wb2api.new.exe" del /Q "wb2api.new.exe" >nul 2>&1
echo Building: "%GO%" build -o wb2api.new.exe ./cmd/server
"%GO%" build -o wb2api.new.exe ./cmd/server
if errorlevel 1 goto BUILDFAIL
if not exist "wb2api.new.exe" goto BUILDFAIL
echo [OK] Build succeeded.
goto LAUNCH

:KILLGATE
%SystemRoot%\System32\taskkill.exe /IM wb2api.exe /F >nul 2>&1
set /a tries=0
:WAITGATE
%SystemRoot%\System32\tasklist.exe /FI "IMAGENAME eq wb2api.exe" 2>nul | %SystemRoot%\System32\find.exe /I "wb2api.exe" >nul
if errorlevel 1 exit /b 0
set /a tries+=1
if %tries% GEQ 10 exit /b 0
%SystemRoot%\System32\ping.exe -n 2 127.0.0.1 >nul
goto WAITGATE

:LAUNCH
if not exist "wb2api.new.exe" goto LAUNCH2
move /Y "wb2api.exe" "wb2api.old.exe" >nul 2>&1
move /Y "wb2api.new.exe" "wb2api.exe" >nul 2>&1
if exist "wb2api.new.exe" goto PROMOTEFAIL
echo [OK] New build applied. Previous kept as wb2api.old.exe
:LAUNCH2
if not exist "wb2api.exe" (
    echo [ERROR] wb2api.exe not found. Use [4] to rebuild it.
    pause
    goto MENU
)
echo Starting WorkBuddy2API gateway in background ...

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { $p = Start-Process -FilePath '.\wb2api.exe' -ArgumentList '-config','config.json' -WorkingDirectory '%~dp0' -WindowStyle Hidden -PassThru } catch { Write-Host ('[ERROR] cannot start: ' + $_.Exception.Message); exit 1 }; Start-Sleep -Seconds 2; if ($p.HasExited) { Write-Host ('[ERROR] gateway exited immediately, exit code = ' + $p.ExitCode); exit 1 }; Write-Host ('[OK] gateway started, PID = ' + $p.Id); try { $r = Invoke-WebRequest -Uri 'http://127.0.0.1:7863/healthz' -UseBasicParsing -TimeoutSec 8; Write-Host ('[OK] healthz = ' + $r.Content) } catch { Write-Host '[WARN] gateway started, but healthz is NOT reachable.'; exit 2 }"

if errorlevel 2 goto WARNSTAY
if errorlevel 1 goto FAIL
echo.
echo [OK] Running in background. Panel: http://127.0.0.1:7863/panel/
goto WAITCLOSE

:STOP
echo.
echo Stopping WorkBuddy2API gateway ...
%SystemRoot%\System32\taskkill.exe /IM wb2api.exe /F >nul 2>&1
if errorlevel 1 (
    echo [SKIP] Nothing to stop - gateway is not running.
) else (
    echo [OK] Stopped.
)
goto WAITCLOSE

:FAIL
echo.
echo Startup failed. Run this manually to see the error:
echo     wb2api.exe -config config.json
echo.
pause
exit /b 1

:BUILDFAIL
echo.
echo [ERROR] Build failed. Existing wb2api.exe was NOT replaced.
if exist "wb2api.new.exe" del /Q "wb2api.new.exe" >nul 2>&1
echo Gateway is stopped. Fix the build error and try [4] again.
echo.
pause
goto MENU

:PROMOTEFAIL
echo.
echo [ERROR] Cannot replace wb2api.exe - it may still be running.
echo Stop the gateway with [2] first, then start again.
echo.
pause
exit /b 1

:WARNSTAY
echo.
echo [WARN] Gateway was started, but its healthz endpoint is NOT reachable.
echo Check the panel, or run it manually to see the logs:
echo     wb2api.exe -config config.json
echo.
pause
exit /b 1

:WAITCLOSE
echo.
echo Done. This window closes in 1.5s ...
powershell -NoProfile -Command "Start-Sleep -Milliseconds 1500"
exit /b 0
