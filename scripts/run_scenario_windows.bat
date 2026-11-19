@echo off
setlocal
REM Builds a scenario from an edited shocks CSV, runs the model, and writes the output package.
REM   scripts\run_scenario_windows.bat <edited.csv> [Output.zip] [description]
REM Defaults: output\<csv name>_Output.zip, description "Scenario from <csv name>". The input
REM package is written beside the output as <stem>_Input.zip. See data\scenarios\README.md.
for %%I in ("%~dp0..") do set "REPO_DIR=%%~fI"
if "%BSAT_LOCAL_DIR%"=="" (set "LOCAL_DIR=%REPO_DIR%\.bsat_local") else (set "LOCAL_DIR=%BSAT_LOCAL_DIR%")
set "JULIA=%LOCAL_DIR%\julia\bin\julia.exe"
set "MODEL_DIR=%REPO_DIR%\code\model"
set "SHOCKS=%~1"
if "%SHOCKS%"=="" ( echo Usage: scripts\run_scenario_windows.bat ^<edited.csv^> [Output.zip] [description] & exit /b 1 )
set "OUTPUT=%~2"
if "%OUTPUT%"=="" set "OUTPUT=%REPO_DIR%\output\%~n1_Output.zip"
set "DESCRIPTION=%~3"
if not exist "%JULIA%" ( echo Julia not found. Run scripts\bootstrap_windows.bat first. & exit /b 1 )
if not exist "%MODEL_DIR%\path_license.txt" ( echo Missing path_license.txt in code\model ^(see path_license.txt.example^). & exit /b 1 )
if not exist "%SHOCKS%" ( echo Shocks CSV not found: %SHOCKS% & exit /b 1 )
for %%D in ("%OUTPUT%") do if not exist "%%~dpD" mkdir "%%~dpD"
if "%DESCRIPTION%"=="" (
  "%JULIA%" --project="%MODEL_DIR%" "%MODEL_DIR%\run_scenario.jl" --shocks "%SHOCKS%" --output "%OUTPUT%"
) else (
  "%JULIA%" --project="%MODEL_DIR%" "%MODEL_DIR%\run_scenario.jl" --shocks "%SHOCKS%" --output "%OUTPUT%" --description "%DESCRIPTION%"
)
