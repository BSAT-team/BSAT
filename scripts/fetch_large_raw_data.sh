#!/usr/bin/env bash
# Obtains the raw files that are not distributed with the repository (all under data/raw/trade_barriers/):
# two are too large for git, three are extracts whose source terms (UNCTAD TRAINS, WTO) do not allow
# redistribution. The pipeline ships their derived products in data/interim/ and reuses them when the raw
# files are absent, so these files are needed only to rerun scripts 22 and 23 from scratch.
#
#   scripts/fetch_large_raw_data.sh            check which files are present and print instructions
#   scripts/fetch_large_raw_data.sh --download download the CEPII BACI archive (about 2.4 GB) and extract the 2014 file
#
# 1. BACI_HS92_Y2014_V202401b.csv  (CEPII BACI, HS92, release 202401b; about 460 MB)
#    Public download: https://www.cepii.fr/DATA_DOWNLOAD/baci/data/BACI_HS92_V202401b.zip
#    The archive holds one CSV per year; only the 2014 file is used. Terms of use: cite BACI
#    (Gaulier and Zignago, 2010) and see https://www.cepii.fr/CEPII/en/bdd_modele/bdd_modele_item.asp?id=37
# 2. tariff_ave_2014_WITS.csv  (World Bank WITS, 2014 applied tariff ad-valorem equivalents; about 245 MB)
# 3. tariff_ave_WITS_2023.csv  (same query for 2023; feeds script 22)
# 4. ag_hs_products.csv        (WITS product group WTO_HS_Aggri: the HS6 codes classed as agricultural)
#    WITS requires a free account and interactive queries: https://wits.worldbank.org/
#    See doc/data-sources.qmd for the query settings and the expected columns.
# 5. ag_tariff_USA_2014.xls    (WTO Tariff and Trade Data, United States applied MFN schedule 2014, sheet Applied_MFN)
#    https://ttd.wto.org/ ; only used to rebuild the commodity-to-HS6 mapping shipped in data/interim/commodity_hs6_mapping.csv
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$REPO_DIR/data/raw/trade_barriers"
BACI_URL="https://www.cepii.fr/DATA_DOWNLOAD/baci/data/BACI_HS92_V202401b.zip"
BACI_FILE="BACI_HS92_Y2014_V202401b.csv"
WITS_FILE="tariff_ave_2014_WITS.csv"
MANUAL_FILES="tariff_ave_2014_WITS.csv tariff_ave_WITS_2023.csv ag_hs_products.csv ag_tariff_USA_2014.xls"
mkdir -p "$DEST"

status() { if [ -f "$DEST/$1" ]; then echo "present  $1 ($(du -hL "$DEST/$1" | cut -f1))"; else echo "MISSING  $1"; fi; }
echo "Raw files not distributed with the repository, in $DEST:"; status "$BACI_FILE"; for f in $MANUAL_FILES; do status "$f"; done

if [ "${1:-}" = "--download" ]; then
  if [ -f "$DEST/$BACI_FILE" ]; then
    echo "BACI 2014 file already present; nothing to download."
  else
    command -v unzip >/dev/null || { echo "unzip is required" >&2; exit 1; }
    TMP="$DEST/BACI_HS92_V202401b.zip"
    echo "Downloading $BACI_URL (about 2.4 GB; resumable)..."
    curl -L -C - --retry 3 -o "$TMP" "$BACI_URL"
    echo "Extracting $BACI_FILE..."
    unzip -o -j "$TMP" "$BACI_FILE" -d "$DEST"
    rm -f "$TMP"
    status "$BACI_FILE"
  fi
fi

missing=0; for f in $MANUAL_FILES; do [ -f "$DEST/$f" ] || missing=1; done
if [ "$missing" = 1 ]; then
  cat <<MSG

The WITS and WTO files must be obtained manually (free accounts):
  tariff_ave_2014_WITS.csv, tariff_ave_WITS_2023.csv: https://wits.worldbank.org/ Advanced Query > Tariff and Trade
      Analysis (TRAINS); all reporters, all partners, all HS6 products, year 2014 (or 2023), AVE of applied tariff; export CSV.
  ag_hs_products.csv: WITS product group WTO_HS_Aggri, exported as CSV with a Product column of HS6 codes.
  ag_tariff_USA_2014.xls: https://ttd.wto.org/ United States, applied MFN tariffs, 2014, Excel export (sheet Applied_MFN).
Save them under those names in $DEST. Query details: doc/data-sources.qmd.
Without them, code/processing/main.R reuses the derived files shipped in data/interim/ for scripts 22 and 23.
MSG
fi
