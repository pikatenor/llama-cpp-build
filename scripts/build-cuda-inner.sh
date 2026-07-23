#!/usr/bin/env bash
# Runs INSIDE the nvidia/cuda:*-cudnn-devel container (working dir = llama.cpp
# checkout, bind-mounted from the host). Builds ONLY the CUDA backend plugin
# with GGML_BACKEND_DL and stages it (plus the CUDA runtime libs) into
# $CUDA_STAGE, which is host-visible so the runner can upload it.
#
# Env: CUDA_ARCHS (semicolon list), CUDA_STAGE (host-visible staging dir).
set -euo pipefail

echo ">>> installing build tools"
apt-get update -qq
apt-get install -y --no-install-recommends git cmake ninja-build build-essential patchelf ca-certificates >/dev/null

# Link against the CUDA driver stubs so the build doesn't need a real GPU.
export LIBRARY_PATH="/usr/local/cuda/lib64/stubs${LIBRARY_PATH:+:$LIBRARY_PATH}"
ln -sf /usr/local/cuda/lib64/stubs/libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so.1

echo ">>> configuring (CUDA_ARCHS=${CUDA_ARCHS:?})"
cmake -S . -B build -G Ninja \
  -DBUILD_SHARED_LIBS=ON -DGGML_BACKEND_DL=ON \
  -DGGML_CUDA=ON -DGGML_CPU=OFF \
  -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCHS}" \
  -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=OFF \
  -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF \
  -DCMAKE_EXE_LINKER_FLAGS="-Wl,-rpath-link,/usr/local/cuda/lib64/stubs" \
  -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-rpath-link,/usr/local/cuda/lib64/stubs"

echo ">>> building"
cmake --build build --config Release -j"$(nproc)"

STAGE="${CUDA_STAGE:-/work/stage}"
mkdir -p "$STAGE"

echo ">>> staging CUDA backend plugin"
# Backend plugin (dlopen'd by filename: libggml-cuda-*.so). cp -a keeps symlinks/SONAME files.
cp -a build/bin/libggml-cuda*.so* "$STAGE/" || { echo "libggml-cuda backend not produced" >&2; ls -la build/bin/ | head; exit 1; }

echo ">>> bundling CUDA runtime next to the backend"
for lib in libcudart.so libcublas.so libcublasLt.so; do
  cp -a /usr/local/cuda/lib64/${lib}* "$STAGE/" 2>/dev/null || echo "  (no $lib in cuda lib64)"
done

echo ">>> setting rpath \$ORIGIN on staged libs"
for f in "$STAGE"/*.so*; do
  [ -f "$f" ] && [ ! -L "$f" ] && patchelf --set-rpath '$ORIGIN' "$f" 2>/dev/null || true
done

echo ">>> staged CUDA backend:"
ls -la "$STAGE"
