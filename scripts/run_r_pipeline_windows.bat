@echo off
setlocal
for %%I in ("%~dp0..") do set "REPO_DIR=%%~fI"
if "%BSAT_LOCAL_DIR%"=="" (set "LOCAL_DIR=%REPO_DIR%\.bsat_local") else (set "LOCAL_DIR=%BSAT_LOCAL_DIR%")
set "MAMBA_ROOT_PREFIX=%LOCAL_DIR%\mamba"
set "MM=%LOCAL_DIR%\bin\micromamba.exe"
if not exist "%MM%" ( echo micromamba not found. Run scripts\bootstrap_windows.bat first. & exit /b 1 )
cd /d "%REPO_DIR%\code\processing"
"%MM%" run -p "%LOCAL_DIR%\envs\bsat" Rscript main.R
