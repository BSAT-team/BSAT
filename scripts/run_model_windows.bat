@echo off
setlocal
REM Runs the BSAT model on an input package and writes an output package.
REM   scripts\run_model_windows.bat [Input.zip] [Output.zip] [years]
REM Defaults: data\packages\baseline_2025_Input.zip, output\baseline_Output.zip, 2025:2034.
for %%I in ("%~dp0..") do set "REPO_DIR=%%~fI"
if "%BSAT_LOCAL_DIR%"=="" (set "LOCAL_DIR=%REPO_DIR%\.bsat_local") else (set "LOCAL_DIR=%BSAT_LOCAL_DIR%")
set "JULIA=%LOCAL_DIR%\julia\bin\julia.exe"
set "MODEL_DIR=%REPO_DIR%\code\model"
set "INPUT=%~1"
if "%INPUT%"=="" set "INPUT=%REPO_DIR%\data\packages\baseline_2025_Input.zip"
set "OUTPUT=%~2"
if "%OUTPUT%"=="" set "OUTPUT=%REPO_DIR%\output\baseline_Output.zip"
set "YEARS=%~3"
if "%YEARS%"=="" set "YEARS=2025:2034"
if not exist "%JULIA%" ( echo Julia not found. Run scripts\bootstrap_windows.bat first. & exit /b 1 )
if not exist "%MODEL_DIR%\path_license.txt" ( echo Missing path_license.txt in code\model ^(see path_license.txt.example^). & exit /b 1 )
if not exist "%INPUT%" ( echo Input package not found: %INPUT% & exit /b 1 )
for %%D in ("%OUTPUT%") do if not exist "%%~dpD" mkdir "%%~dpD"
"%JULIA%" --project="%MODEL_DIR%" "%MODEL_DIR%\run_model.jl" --input "%INPUT%" --output "%OUTPUT%" --years "%YEARS%"
