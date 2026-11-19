#!/usr/bin/env bash
# Builds a scenario from an edited shocks CSV, runs the model, and writes the output package.
#   scripts/run_scenario_unix.sh <edited.csv> [Output.zip] [description]
# Defaults: output/<csv name>_Output.zip, description "Scenario from <csv name>". The input
# package is written beside the output as <stem>_Input.zip. See data/scenarios/README.md.
# Uses the portable Julia under .bsat_local/ when present, else the Julia on PATH.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_DIR="${BSAT_LOCAL_DIR:-$REPO_DIR/.bsat_local}"
MODEL_DIR="$REPO_DIR/code/model"
[ $# -ge 1 ] || { echo "Usage: scripts/run_scenario_unix.sh <edited.csv> [Output.zip] [description]" >&2; exit 1; }
SHOCKS="$1"
STEM="$(basename "$SHOCKS" .csv)"
OUTPUT="${2:-$REPO_DIR/output/${STEM}_Output.zip}"

if [ -x "$LOCAL_DIR/julia/bin/julia" ]; then
  JULIA="$LOCAL_DIR/julia/bin/julia"
elif command -v julia >/dev/null 2>&1; then
  JULIA="$(command -v julia)"
else
  echo "Julia not found. Run scripts/bootstrap_unix.sh first (local install), or use the devcontainer." >&2
  exit 1
fi
[ -f "$MODEL_DIR/path_license.txt" ] || { echo "Missing $MODEL_DIR/path_license.txt: paste your PATH license (see path_license.txt.example)." >&2; exit 1; }
[ -f "$SHOCKS" ] || { echo "Shocks CSV not found: $SHOCKS" >&2; exit 1; }

mkdir -p "$(dirname "$OUTPUT")"
if [ $# -ge 3 ]; then
  exec "$JULIA" --project="$MODEL_DIR" "$MODEL_DIR/run_scenario.jl" --shocks "$SHOCKS" --output "$OUTPUT" --description "$3"
else
  exec "$JULIA" --project="$MODEL_DIR" "$MODEL_DIR/run_scenario.jl" --shocks "$SHOCKS" --output "$OUTPUT"
fi
