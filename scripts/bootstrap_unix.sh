#!/usr/bin/env bash
# Portable, no-admin bootstrap for BSAT (macOS/Linux).
# Installs micromamba, the 'bsat' R environment, portable Julia and its packages, and (optionally)
# the 'bsat-dashboard' Python environment, all under BSAT_LOCAL_DIR (default: .bsat_local inside the repo).
#   scripts/bootstrap_unix.sh                  everything
#   scripts/bootstrap_unix.sh --no-dashboard   skip the Python environment for the local dashboard
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_DIR="${BSAT_LOCAL_DIR:-$REPO_DIR/.bsat_local}"
WITH_DASHBOARD=1; [ "${1:-}" = "--no-dashboard" ] && WITH_DASHBOARD=0
JULIA_VER="1.12.1"
JULIA_MINOR="1.12"
mkdir -p "$LOCAL_DIR/bin"
echo "Installing under $LOCAL_DIR"

OS="$(uname -s)"; ARCH="$(uname -m)"
case "$OS-$ARCH" in
  Linux-x86_64)  MM_URL="https://github.com/mamba-org/micromamba-releases/releases/download/2.8.1-0/micromamba-linux-64";      JL_URL="https://julialang-s3.julialang.org/bin/linux/x64/${JULIA_MINOR}/julia-${JULIA_VER}-linux-x86_64.tar.gz" ;;
  Linux-aarch64) MM_URL="https://github.com/mamba-org/micromamba-releases/releases/download/2.8.1-0/micromamba-linux-aarch64"; JL_URL="https://julialang-s3.julialang.org/bin/linux/aarch64/${JULIA_MINOR}/julia-${JULIA_VER}-linux-aarch64.tar.gz" ;;
  Darwin-x86_64) MM_URL="https://github.com/mamba-org/micromamba-releases/releases/download/2.8.1-0/micromamba-osx-64";        JL_URL="https://julialang-s3.julialang.org/bin/mac/x64/${JULIA_MINOR}/julia-${JULIA_VER}-mac64.tar.gz" ;;
  Darwin-arm64)  MM_URL="https://github.com/mamba-org/micromamba-releases/releases/download/2.8.1-0/micromamba-osx-arm64";     JL_URL="https://julialang-s3.julialang.org/bin/mac/aarch64/${JULIA_MINOR}/julia-${JULIA_VER}-macaarch64.tar.gz" ;;
  *) echo "Unsupported platform: $OS-$ARCH" >&2; exit 1 ;;
esac

MM="$LOCAL_DIR/bin/micromamba"
if [ ! -x "$MM" ]; then
  echo "Downloading micromamba..."
  curl -L "$MM_URL" -o "$MM"; chmod +x "$MM"
fi
export MAMBA_ROOT_PREFIX="$LOCAL_DIR/mamba"

# Create an environment; retry once after clearing the package cache.
create_env() {
  local name="$1" file="$2"
  rm -rf "$LOCAL_DIR/envs/$name" 2>/dev/null || {
    echo "Could not remove the old environment at $LOCAL_DIR/envs/$name: some files are not yours" >&2
    echo "(for example, created by a Docker run as root). Delete it by hand, then rerun this script:" >&2
    echo "  sudo rm -rf \"$LOCAL_DIR/envs/$name\"" >&2
    return 1
  }
  "$MM" create -y -p "$LOCAL_DIR/envs/$name" -f "$file" && return 0
  echo "First attempt failed, clearing the package cache and retrying once"
  "$MM" clean -a -y >/dev/null 2>&1 || true
  rm -rf "$LOCAL_DIR/mamba/pkgs" "$LOCAL_DIR/envs/$name"
  "$MM" create -y -p "$LOCAL_DIR/envs/$name" -f "$file"
}

# ---- R environment (required by the pipeline) ----
# Kept only if its R version matches the r-base pin in setup/environment.yml; otherwise recreated.
R_REQ="$(sed -n 's/^ *- r-base=\([0-9.]*\).*/\1/p' "$REPO_DIR/setup/environment.yml")"
if compgen -G "$LOCAL_DIR/envs/bsat/conda-meta/r-base-${R_REQ:-*}.*.json" >/dev/null; then
  echo "'bsat' R environment already present (R ${R_REQ}), skipping."
else
  [ -f "$LOCAL_DIR/envs/bsat/conda-meta/history" ] && echo "The existing 'bsat' environment has another R version; recreating it with R ${R_REQ}."
  echo "Creating the 'bsat' R environment (several minutes)..."
  create_env bsat "$REPO_DIR/setup/environment.yml"
fi

# ---- Julia and the model packages (required by the model) ----
JULIA_HOME="$LOCAL_DIR/julia"
if [ ! -x "$JULIA_HOME/bin/julia" ]; then
  echo "Downloading Julia ${JULIA_VER}..."
  curl -L "$JL_URL" -o "$LOCAL_DIR/julia.tar.gz"
  mkdir -p "$JULIA_HOME"
  tar -xzf "$LOCAL_DIR/julia.tar.gz" -C "$JULIA_HOME" --strip-components=1
  rm -f "$LOCAL_DIR/julia.tar.gz"
fi
echo "Installing Julia packages (JuMP, PATHSolver, ...)..."
"$JULIA_HOME/bin/julia" --project="$REPO_DIR/code/model" -e 'import Pkg; Pkg.instantiate(); Pkg.precompile()'

# ---- Python environment for the local dashboard (optional) ----
if [ "$WITH_DASHBOARD" = 0 ]; then
  echo "Skipping the dashboard environment (--no-dashboard)."
elif [ -f "$LOCAL_DIR/envs/bsat-dashboard/conda-meta/history" ]; then
  echo "'bsat-dashboard' environment already present, skipping."
else
  echo "Creating the 'bsat-dashboard' Python environment (optional, several minutes)..."
  if ! create_env bsat-dashboard "$REPO_DIR/setup/environment-dashboard.yml"; then
    echo "WARNING: the dashboard environment could not be created. The model and the pipeline are unaffected."
    echo "         Use the hosted dashboard, or rerun scripts/bootstrap_unix.sh later."
  fi
fi

echo
echo "Bootstrap complete. Next:"
echo "  1. Paste your PATH license into code/model/path_license.txt (see path_license.txt.example)"
echo "  2. Run the model:      scripts/run_model_unix.sh"
echo "  3. Run the R pipeline: scripts/run_r_pipeline_unix.sh"
echo "  4. Local dashboard:    scripts/run_dashboard_unix.sh (or use the hosted copy)"
