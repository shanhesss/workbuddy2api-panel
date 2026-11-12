@echo off
rem Daily update: merge misaka/main into misaka-sync. Never pushes, never rebuilds.
setlocal EnableExtensions
set "REPO=D:\hklfile\workspace\workbuddy-proxy"
set "LOG=%REPO%\data\update-sync.log"
set "PATH=C:\Program Files\Git\cmd;%PATH%"

cd /d "%REPO%" || exit /b 1
if not exist "%REPO%\data" mkdir "%REPO%\data"

echo.>>"%LOG%"
echo ===== %date:~0,10% %time:~0,8% =====>>"%LOG%"

if exist ".git\MERGE_HEAD" (
  echo [SKIP] merge already in progress; resolve it manually>>"%LOG%"
  exit /b 3
)

for /f "delims=" %%b in ('git rev-parse --abbrev-ref HEAD') do set "BRANCH=%%b"
if not "%BRANCH%"=="misaka-sync" (
  echo [SKIP] current branch is %BRANCH%, not misaka-sync>>"%LOG%"
  exit /b 4
)

set "DIRTY="
for /f "delims=" %%s in ('git status --porcelain --untracked-files=no') do set "DIRTY=1"
if defined DIRTY (
  echo [SKIP] tracked files modified; commit or discard changes first>>"%LOG%"
  exit /b 5
)

git fetch misaka>>"%LOG%" 2>&1
if errorlevel 1 (
  echo [FAIL] git fetch misaka failed>>"%LOG%"
  exit /b 6
)

set "NEW=0"
for /f "delims=" %%c in ('git rev-list --count HEAD..misaka/main') do set "NEW=%%c"
if "%NEW%"=="0" (
  echo [OK] already up to date>>"%LOG%"
  exit /b 0
)

echo [INFO] merging %NEW% new commit^(s^) from misaka/main>>"%LOG%"
git merge --no-edit misaka/main>>"%LOG%" 2>&1
if errorlevel 1 (
  git merge --abort>>"%LOG%" 2>&1
  echo [FAIL] merge conflict; aborted, resolve manually>>"%LOG%"
  exit /b 7
)

echo [OK] merged. NOT pushed, NOT rebuilt>>"%LOG%"
exit /b 0
