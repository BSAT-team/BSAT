@echo off
setlocal
REM Obtains the two raw files that are too large for the repository (see fetch_large_raw_data.sh for details).
REM   scripts\fetch_large_raw_data.bat            check which files are present
REM   scripts\fetch_large_raw_data.bat --download download the CEPII BACI archive (about 2.4 GB) and extract the 2014 file
for %%I in ("%~dp0..") do set "REPO_DIR=%%~fI"
set "DEST=%REPO_DIR%\data\raw\trade_barriers"
set "BACI_URL=https://www.cepii.fr/DATA_DOWNLOAD/baci/data/BACI_HS92_V202401b.zip"
set "BACI_FILE=BACI_HS92_Y2014_V202401b.csv"
if not exist "%DEST%" mkdir "%DEST%"
echo Large raw files in %DEST%:
if exist "%DEST%\%BACI_FILE%" (echo present  %BACI_FILE%) else (echo MISSING  %BACI_FILE%)
if "%~1"=="--download" (
  if exist "%DEST%\%BACI_FILE%" (
    echo BACI 2014 file already present; nothing to download.
  ) else (
    echo Downloading %BACI_URL% ^(about 2.4 GB^)...
    curl -L --retry 3 -o "%DEST%\BACI_HS92_V202401b.zip" "%BACI_URL%"
    echo Extracting %BACI_FILE%...
    powershell -NoProfile -Command "Add-Type -AssemblyName System.IO.Compression.FileSystem; $z=[IO.Compression.ZipFile]::OpenRead('%DEST%\BACI_HS92_V202401b.zip'); $e=$z.GetEntry('%BACI_FILE%'); [IO.Compression.ZipFileExtensions]::ExtractToFile($e, '%DEST%\%BACI_FILE%', $true); $z.Dispose()"
    del "%DEST%\BACI_HS92_V202401b.zip"
  )
)
for %%F in (tariff_ave_2014_WITS.csv tariff_ave_WITS_2023.csv ag_hs_products.csv ag_tariff_USA_2014.xls) do (
  if exist "%DEST%\%%F" (echo present  %%F) else (echo MISSING  %%F)
)
echo.
echo WITS files ^(free account, https://wits.worldbank.org/^): TRAINS tariff AVE queries for 2014 and 2023, and the
echo WTO_HS_Aggri product group; WTO file ^(https://ttd.wto.org/^): United States applied MFN 2014. See doc\data-sources.qmd.
echo Without them, code\processing\main.R reuses the derived files shipped in data\interim for scripts 22 and 23.
