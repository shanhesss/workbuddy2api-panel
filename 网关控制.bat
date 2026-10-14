@echo off
chcp 65001 >nul
cd /d "%~dp0"
title WorkBuddy2API Gateway control

if not exist "wb2api.exe" (
    echo [ERROR] wb2api.exe not found in this folder. Build it first.
    pause
    exit /b 1
)

:MENU
cls
set RUNNING=no
%SystemRoot%\System32\tasklist.exe /FI "IMAGENAME eq wb2api.exe" 2>nul | %SystemRoot%\System32\find.exe /I "wb2api.exe" >nul && set RUNNING=yes

echo ==============================================
echo   WorkBuddy2API Gateway control
echo ==============================================
echo   Status: %RUNNING%
echo.
echo   [1] Start   (background, silent - safe to close)
echo   [2] Stop
echo   [3] Restart (stop, apply new build if any, start)
echo   [0] Quit
echo ==============================================
set "choice="
set /p "choice=Type 1, 2 or 3, then press Enter: "

if "%choice%"=="1" goto START
if "%choice%"=="2" goto STOP
if "%choice%"=="3" goto RESTART
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

:LAUNCH
if not exist "wb2api.new.exe" goto LAUNCH2
move /Y "wb2api.exe" "wb2api.old.exe" >nul 2>&1
move /Y "wb2api.new.exe" "wb2api.exe" >nul 2>&1
if exist "wb2api.new.exe" goto PROMOTEFAIL
echo [OK] New build applied. Previous kept as wb2api.old.exe
:LAUNCH2
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
