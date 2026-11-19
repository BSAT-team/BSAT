#!/usr/bin/env bash
# Runs the BSAT model on an input package and writes an output package.
#   scripts/run_model_unix.sh [Input.zip] [Output.zip] [years]
# Defaults: data/packages/baseline_2025_Input.zip, output/baseline_Output.zip, 2025:2034.
# Uses the portable Julia under .bsat_local/ when present, else the Julia on PATH.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_DIR="${BSAT_LOCAL_DIR:-$REPO_DIR/.bsat_local}"
MODEL_DIR="$REPO_DIR/code/model"
INPUT="${1:-$REPO_DIR/data/packages/baseline_2025_Input.zip}"
OUTPUT="${2:-$REPO_DIR/output/baseline_Output.zip}"
YEARS="${3:-2025:2034}"

if [ -x "$LOCAL_DIR/julia/bin/julia" ]; then
  JULIA="$LOCAL_DIR/julia/bin/julia"
elif command -v julia >/dev/null 2>&1; then
  JULIA="$(command -v julia)"
else
  echo "Julia not found. Run scripts/bootstrap_unix.sh first (local install), or use the devcontainer." >&2
  exit 1
fi
[ -f "$MODEL_DIR/path_license.txt" ] || { echo "Missing $MODEL_DIR/path_license.txt: paste your PATH license (see path_license.txt.example)." >&2; exit 1; }
[ -f "$INPUT" ] || { echo "Input package not found: $INPUT" >&2; exit 1; }

mkdir -p "$(dirname "$OUTPUT")"
exec "$JULIA" --project="$MODEL_DIR" "$MODEL_DIR/run_model.jl" --input "$INPUT" --output "$OUTPUT" --years "$YEARS"
