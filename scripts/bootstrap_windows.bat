@echo off
setlocal enabledelayedexpansion
REM Portable, no-admin bootstrap for BSAT (Windows).
REM Installs micromamba, the 'bsat' R environment, portable Julia and its packages, and (optionally)
REM the 'bsat-dashboard' Python environment, all under BSAT_LOCAL_DIR (default: .bsat_local inside the repo).
REM   scripts\bootstrap_windows.bat                  everything
REM   scripts\bootstrap_windows.bat --no-dashboard   skip the Python environment for the local dashboard
REM   set BSAT_LOCAL_DIR=C:\bsat_local               use a short path if package extraction fails on long paths
for %%I in ("%~dp0..") do set "REPO_DIR=%%~fI"
if "%BSAT_LOCAL_DIR%"=="" (set "LOCAL_DIR=%REPO_DIR%\.bsat_local") else (set "LOCAL_DIR=%BSAT_LOCAL_DIR%")
set "WITH_DASHBOARD=1"
if /I "%~1"=="--no-dashboard" set "WITH_DASHBOARD=0"
set "JULIA_VER=1.12.1"
set "JULIA_MINOR=1.12"
if not exist "%LOCAL_DIR%\bin" mkdir "%LOCAL_DIR%\bin"
echo Installing under %LOCAL_DIR%

set "MM=%LOCAL_DIR%\bin\micromamba.exe"
if not exist "%MM%" (
  echo Downloading micromamba
  curl -L "https://github.com/mamba-org/micromamba-releases/releases/download/2.8.1-0/micromamba-win-64.exe" -o "%MM%"
  if errorlevel 1 goto :error
)
set "MAMBA_ROOT_PREFIX=%LOCAL_DIR%\mamba"

REM ---- R environment (required by the pipeline) ----
REM Kept only if its R version matches the r-base pin in setup\environment.yml; otherwise recreated.
set "R_REQ="
for /f "tokens=2 delims==" %%V in ('findstr /r /c:"^ *- r-base=" "%REPO_DIR%\setup\environment.yml"') do set "R_REQ=%%V"
if not defined R_REQ set "R_REQ=*"
if exist "%LOCAL_DIR%\envs\bsat\conda-meta\r-base-%R_REQ%.*.json" (
  echo 'bsat' R environment already present with R %R_REQ%, skipping
) else (
  if exist "%LOCAL_DIR%\envs\bsat\conda-meta\history" echo The existing 'bsat' environment has another R version, recreating it with R %R_REQ%
  echo Creating the 'bsat' R environment, several minutes
  call :create_env bsat "%REPO_DIR%\setup\environment.yml"
  if errorlevel 1 goto :error
)

REM ---- Julia and the model packages (required by the model) ----
set "JULIA_HOME=%LOCAL_DIR%\julia"
if not exist "%JULIA_HOME%\bin\julia.exe" (
  echo Downloading Julia %JULIA_VER%
  curl -L "https://julialang-s3.julialang.org/bin/winnt/x64/%JULIA_MINOR%/julia-%JULIA_VER%-win64.zip" -o "%LOCAL_DIR%\julia.zip"
  if errorlevel 1 goto :error
  echo Extracting Julia
  powershell -NoProfile -Command "Expand-Archive -Force '%LOCAL_DIR%\julia.zip' '%LOCAL_DIR%\julia_tmp'"
  for /d %%D in ("%LOCAL_DIR%\julia_tmp\julia-*") do move "%%D" "%JULIA_HOME%" >nul
  rmdir /s /q "%LOCAL_DIR%\julia_tmp"
  del "%LOCAL_DIR%\julia.zip"
)
echo Installing Julia packages, JuMP and PATHSolver among them
"%JULIA_HOME%\bin\julia.exe" --project="%REPO_DIR%\code\model" -e "import Pkg; Pkg.instantiate(); Pkg.precompile()"
if errorlevel 1 goto :error

REM ---- Python environment for the local dashboard (optional) ----
if "%WITH_DASHBOARD%"=="0" (
  echo Skipping the dashboard environment, --no-dashboard
) else if exist "%LOCAL_DIR%\envs\bsat-dashboard\conda-meta\history" (
  echo 'bsat-dashboard' environment already present, skipping
) else (
  echo Creating the 'bsat-dashboard' Python environment, optional, several minutes
  call :create_env bsat-dashboard "%REPO_DIR%\setup\environment-dashboard.yml"
  if errorlevel 1 (
    echo WARNING: the dashboard environment could not be created. The model and the pipeline are unaffected.
    echo          Use the hosted dashboard, or retry later with: scripts\bootstrap_windows.bat
  )
)

echo.
echo Bootstrap complete. Next:
echo   1. Paste your PATH license into code\model\path_license.txt, see path_license.txt.example
echo   2. Run the model:      scripts\run_model_windows.bat
echo   3. Run the R pipeline: scripts\run_r_pipeline_windows.bat
echo   4. Local dashboard:    scripts\run_dashboard_windows.bat, or use the hosted copy
goto :eof

:create_env
REM %1 = environment name, %2 = environment file. Removes a partial environment, retries once after clearing the cache.
if exist "%LOCAL_DIR%\envs\%~1" rmdir /s /q "%LOCAL_DIR%\envs\%~1"
"%MM%" create -y -p "%LOCAL_DIR%\envs\%~1" -f "%~2"
if not errorlevel 1 exit /b 0
echo First attempt failed, clearing the package cache and retrying once
"%MM%" clean -a -y >nul 2>&1
if exist "%LOCAL_DIR%\mamba\pkgs" rmdir /s /q "%LOCAL_DIR%\mamba\pkgs"
if exist "%LOCAL_DIR%\envs\%~1" rmdir /s /q "%LOCAL_DIR%\envs\%~1"
"%MM%" create -y -p "%LOCAL_DIR%\envs\%~1" -f "%~2"
if not errorlevel 1 exit /b 0
echo.
echo Environment '%~1' could not be created. Common causes on Windows:
echo   - long paths: rerun after  set BSAT_LOCAL_DIR=C:\bsat_local  ^(a short folder^)
echo   - a corporate proxy or antivirus interfering with downloads or extraction: see doc\installation\troubleshooting.qmd
exit /b 1

:error
echo Bootstrap FAILED. See messages above.
exit /b 1
