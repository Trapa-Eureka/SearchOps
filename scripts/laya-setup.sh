#!/usr/bin/env bash
# Installs Laya (optional natural-language intent classifier) into an isolated virtualenv
# under tools/laya (git-ignored). Nothing here is needed for the core search flow.
#
#   scripts/laya-setup.sh            install the package, then download the checkpoints (~2.3 GB)
#   LAYA_PYTHON=python3.11 scripts/laya-setup.sh
#
# Model files go to tools/laya/hf_cache (HF_HOME) unless your shell already sets HF_HUB_CACHE,
# which takes precedence and is reused as is (no second copy is downloaded).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/tools/laya"
LAYA_VERSION="${LAYA_VERSION:-0.4.15}"   # pinned: the HTTP contract in docs/laya-contract.md was read from this version
PYTHON="${LAYA_PYTHON:-python3.12}"

command -v uv >/dev/null || { echo "uv is required (brew install uv)"; exit 1; }
command -v "$PYTHON" >/dev/null || { echo "$PYTHON not found. Laya needs Python >= 3.10 (set LAYA_PYTHON)"; exit 1; }

mkdir -p "$TOOLS"
[ -d "$TOOLS/.venv" ] || uv venv --python "$PYTHON" "$TOOLS/.venv"
uv pip install --python "$TOOLS/.venv/bin/python" "laya[serve]==$LAYA_VERSION"

echo "Installed: $("$TOOLS/.venv/bin/python" -c 'import importlib.metadata as m; print("laya", m.version("laya"))')"

# Download the checkpoints used by SearchOps. "typed-decisions" is fine-tuned for four unrelated
# workflows (customer service, invoices, security incidents, agent traces) and is not needed;
# add it with: LAYA_CHECKPOINTS="english multilingual typed-decisions" scripts/laya-setup.sh
export HF_HOME="${HF_HOME:-$TOOLS/hf_cache}"
CHECKPOINTS="${LAYA_CHECKPOINTS:-english multilingual}"
echo "Downloading checkpoints into $HF_HOME: $CHECKPOINTS"
"$TOOLS/.venv/bin/python" - $CHECKPOINTS <<'PY'
import sys, time
from laya import Router

names = sys.argv[1:]
start = time.time()
router = Router(default=names[0])
router.preload(names)
print("loaded checkpoints:", names, "in %.0fs" % (time.time() - start))
PY
echo "model cache: ${HF_HUB_CACHE:-$HF_HOME/hub}"
