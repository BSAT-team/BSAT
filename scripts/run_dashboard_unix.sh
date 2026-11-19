#!/usr/bin/env bash
# Optional: serve the Streamlit dashboard locally (the hosted copy is https://huggingface.co/spaces/bsat-team/BSAT_Viz).
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_DIR="${BSAT_LOCAL_DIR:-$REPO_DIR/.bsat_local}"

if [ -x "$LOCAL_DIR/bin/micromamba" ]; then
  MM="$LOCAL_DIR/bin/micromamba"
  export MAMBA_ROOT_PREFIX="$LOCAL_DIR/mamba"
elif command -v micromamba >/dev/null 2>&1; then
  MM="$(command -v micromamba)"
else
  echo "micromamba not found. Run scripts/bootstrap_unix.sh first (local install), or use the devcontainer." >&2
  exit 1
fi
if [ -d "$LOCAL_DIR/envs/bsat-dashboard" ]; then
  ENV="$LOCAL_DIR/envs/bsat-dashboard"
elif [ -n "${BSAT_DASHBOARD_ENV:-}" ]; then
  ENV="$BSAT_DASHBOARD_ENV"
elif [ -d "/opt/envs/bsat-dashboard" ]; then
  ENV="/opt/envs/bsat-dashboard"
else
  echo "bsat-dashboard environment not found. Run scripts/bootstrap_unix.sh (local install) or use the devcontainer; the hosted dashboard is at https://huggingface.co/spaces/bsat-team/BSAT_Viz" >&2
  exit 1
fi

cd "$REPO_DIR/code/visualization"
exec "$MM" run -p "$ENV" streamlit run app.py
