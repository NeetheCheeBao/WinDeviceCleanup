@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
cd /d "%ROOT%"

if not defined DOTNET set "DOTNET=dotnet"
if not defined FXC    set "FXC=WinDeviceCleanup.exe"

where "%DOTNET%" >nul 2>&1
if errorlevel 1 (
  echo ERROR: "%DOTNET%" not found on PATH.
  echo Install the .NET SDK from https://dot.net
  echo Or set DOTNET= to the full path of dotnet.exe
  echo.
  pause
  exit /b 1
)

set "PROJ=%ROOT%\src\WinDeviceCleanup.csproj"
set "OUTDIR=%ROOT%\dist"
set "OUT=%OUTDIR%\%FXC%"
set "STRAY=%ROOT%\src\dist"
set "OBJDIR=%TEMP%\WinDeviceCleanup_build"
set "RESTORELOG=%TEMP%\WinDeviceCleanup_restore.log"
set "BUILDLOG=%TEMP%\WinDeviceCleanup_build.log"

if not exist "%PROJ%" (
  echo ERROR: project file not found:
  echo        %PROJ%
  echo.
  pause
  exit /b 1
)

set /a TOTAL=3
set /a STEP=0

if not exist "%OUTDIR%" mkdir "%OUTDIR%"
taskkill /F /IM %FXC% >nul 2>&1

call :progress "clean"
if exist "%OBJDIR%" rmdir /s /q "%OBJDIR%" >nul 2>&1
mkdir "%OBJDIR%" 2>nul
del /f /q "%RESTORELOG%" "%BUILDLOG%" >nul 2>&1
if exist "%OUT%" del /f /q "%OUT%" >nul 2>&1
if exist "%STRAY%" rmdir /s /q "%STRAY%" >nul 2>&1

call :progress "restore"
"%DOTNET%" restore "%PROJ%" --nologo -v quiet >"%RESTORELOG%" 2>&1
if errorlevel 1 (
  echo.
  echo --- restore output ---
  type "%RESTORELOG%"
  goto :fail
)

call :progress "publish"
"%DOTNET%" publish "%PROJ%" -c Release -o "%OUTDIR%" --nologo -v minimal >"%BUILDLOG%" 2>&1
if errorlevel 1 (
  echo.
  echo --- publish output ---
  type "%BUILDLOG%"
  goto :fail
)

if not exist "%OUT%" (
  echo.
  echo ERROR: publish reported success but the exe was not produced at:
  echo        %OUT%
  if exist "%BUILDLOG%" type "%BUILDLOG%"
  goto :fail
)
if exist "%STRAY%" rmdir /s /q "%STRAY%" >nul 2>&1

for %%A in ("%OUT%") do set "SIZE=%%~zA"
set /a "SIZEKB=%SIZE%/1024"

if exist "%OUT%.config" del /f /q "%OUT%.config" >nul 2>&1
if exist "%OBJDIR%" rmdir /s /q "%OBJDIR%" >nul 2>&1
del /f /q "%RESTORELOG%" "%BUILDLOG%" >nul 2>&1

echo.
echo BUILD OK  -^> dist\%FXC%  (%SIZEKB% KB)
call :hold 3
exit /b 0

:fail
echo.
echo BUILD FAILED
if exist "%OBJDIR%" rmdir /s /q "%OBJDIR%" >nul 2>&1
echo.
pause
exit /b 1

:hold
echo.
timeout /t %~1 /nobreak >nul
goto :eof

:progress
set /a STEP+=1
set /a "pct=STEP*100/TOTAL"
set /a "filled=STEP*30/TOTAL"
if !filled! gtr 30 set "filled=30"
set "bar="
for /L %%i in (1,1,30) do (
  if %%i LEQ !filled! (set "bar=!bar!=") else (set "bar=!bar! ")
)
echo [!bar!] !pct!%%  %~1
goto :eof
