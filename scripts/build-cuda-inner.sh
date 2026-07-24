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

echo ">>> bundling CUDA runtime deps of the backend"
# Auto-discover every runtime dep of the CUDA backend with ldd (cuBLAS, cuBLASLt,
# cudart, NCCL, ...) and copy the real file content under each SONAME name (no
# symlinks, so upload-artifact cannot triplicate them). Skip link-only stubs and
# core system libs; the NVIDIA driver (libcuda.so.1) is provided by the host.
ldd build/bin/libggml-cuda*.so* | awk '/=> \// {print $1, $3}' | sort -u | \
while read -r soname path; do
  case "$soname" in
    libc.so.*|libm.so.*|libdl.so.*|libpthread.so.*|librt.so.*|libresolv.so.*|libstdc++.so.*|libgcc_s.so.*|libgomp.so.*|ld-linux*) ;;
    *) case "$path" in
         */stubs/*) ;;
         *) cp -aL "$path" "$STAGE/$soname" 2>/dev/null || true ;;
       esac ;;
  esac
done

echo ">>> setting rpath \$ORIGIN on staged libs"
for f in "$STAGE"/*.so*; do
  [ -f "$f" ] && [ ! -L "$f" ] && patchelf --set-rpath '$ORIGIN' "$f" 2>/dev/null || true
done

echo ">>> staged CUDA backend:"
ls -la "$STAGE"
