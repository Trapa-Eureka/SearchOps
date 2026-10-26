#!/usr/bin/env bash
# Starts laya-serve (FastAPI) on localhost for the Rails app. Run it in its own terminal.
#
#   scripts/laya-serve.sh
#
# Binds to 127.0.0.1 only. Set LAYA_API_KEY to require a bearer token (then put the same
# value in backend/.env). The first start loads the models and takes a while.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/tools/laya"
[ -x "$TOOLS/.venv/bin/python" ] || { echo "Run scripts/laya-setup.sh first"; exit 1; }

export HF_HOME="${HF_HOME:-$TOOLS/hf_cache}"
# Pin the checkpoint commit that the contract and the evaluation in docs/ were measured on.
export LAYA_REVISION="${LAYA_REVISION:-7b928d828b7b0e022f929d9bd2e44165aa270148}"
export LAYA_HOST="${LAYA_HOST:-127.0.0.1}"
export LAYA_PORT="${LAYA_PORT:-8765}"
export LAYA_MODELS="${LAYA_MODELS:-multilingual}"     # which checkpoints to keep loaded
export LAYA_DEFAULT_MODEL="${LAYA_DEFAULT_MODEL:-multilingual}"
export LAYA_MAX_LOADED="${LAYA_MAX_LOADED:-1}"
exec "$TOOLS/.venv/bin/python" -m laya.serve
