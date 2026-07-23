#!/usr/bin/env bash
# Backend-selection launcher for the multi-backend llama.cpp package.
#
#   ./run.sh <cuda|rocm|vulkan|cpu|all> [llama-server args...]
#
# ggml auto-loads every libggml-*.so it finds next to the executable. This
# launcher exposes only the requested vendor's backend .so in bin/ (by
# symlinking them in) and sets LD_LIBRARY_PATH so the backend finds its bundled
# runtime, then execs the frontend. Works across llama.cpp versions without
# relying on the GGML_BACKEND_PATH file/dir ambiguity.
#
# Override the binary with LLAMA_BIN (default: llama-server), e.g.:
#   LLAMA_BIN=llama-cli ./run.sh cuda -m model.gguf -p hi
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BIN_DIR="$SCRIPT_DIR/bin"
BACKEND_DIR="$SCRIPT_DIR/backends"

[ -d "$BIN_DIR" ] || { echo "bin/ not found at $BIN_DIR" >&2; exit 1; }

# Parse the vendor argument (default: all). If the first arg looks like an
# option or is unknown, fall back to "all" and keep the args.
vendor="${1:-all}"
case "$vendor" in
  cuda|rocm|vulkan|cpu|all) shift || true ;;
  *) vendor="all" ;;
esac

# Remove any GPU backend symlinks currently visible in bin/.
find "$BIN_DIR" -maxdepth 1 -type l \
  \( -name 'libggml-cuda-*.so' -o -name 'libggml-hip-*.so' -o -name 'libggml-vulkan-*.so' \) \
  -delete 2>/dev/null || true

link_vendor() {
  local v="$1" src="$BACKEND_DIR/$1"
  [ -d "$src" ] || { echo "warning: backends/$v not present, skipping" >&2; return 0; }
  for so in "$src"/libggml-*.so; do
    [ -e "$so" ] || continue
    ln -sf "../backends/$v/$(basename "$so")" "$BIN_DIR/$(basename "$so")"
  done
  export LD_LIBRARY_PATH="$src${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
}

case "$vendor" in
  cuda|rocm|vulkan) link_vendor "$vendor" ;;
  all) for v in cuda rocm vulkan; do link_vendor "$v"; done ;;
  cpu) ;;  # CPU backend only (already shipped in bin/)
esac

BIN="${LLAMA_BIN:-llama-server}"
echo ">> launching $BIN with backend: $vendor" >&2
exec "$BIN_DIR/$BIN" "$@"
