#!/usr/bin/env bash
# Runs INSIDE the rocm/dev-ubuntu-22.04:6.1.2-complete container (working dir =
# llama.cpp checkout, bind-mounted from the host). Builds ONLY the HIP backend
# plugin for legacy gfx90x targets (MI50/Radeon VII gfx906, MI100 gfx908,
# MI210 gfx90a — CDNA1/Vega20, dropped by newer ROCm) with GGML_BACKEND_DL and
# stages it (plus the ROCm 6.1.2 runtime libs) into $ROCM_STAGE, which is
# host-visible so the runner can upload it. Staging happens in here because
# the host runner has no /opt/rocm.
#
# Env: GPU_TARGETS_LEGACY (semicolon list), ROCM_STAGE (host-visible staging dir).
set -euo pipefail

echo ">>> ROCm in image: $(cat /opt/rocm/.info/version 2>/dev/null || echo unknown)"

echo ">>> installing build tools"
apt-get update -qq
apt-get install -y --no-install-recommends git cmake ninja-build build-essential patchelf ca-certificates >/dev/null

export ROCM_PATH=/opt/rocm
export HIP_PATH=/opt/rocm
export HIP_PLATFORM=amd
export HIP_CLANG_PATH=/opt/rocm/llvm/bin
export PATH="/opt/rocm/bin:/opt/rocm/llvm/bin${PATH:+:$PATH}"
export LD_LIBRARY_PATH="/opt/rocm/lib:/opt/rocm/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# NOTE: deliberately NOT setting HIP_DEVICE_LIB_PATH. That path matches
# TheRock's layout (/opt/rocm/lib/llvm/amdgcn/bitcode); official ROCm 6.1.2
# keeps bitcode at /opt/rocm/amdgcn/bitcode and hipcc finds it on its own.

echo ">>> configuring (GPU_TARGETS=${GPU_TARGETS_LEGACY:?})"
GPU_TARGETS="${GPU_TARGETS_LEGACY}"
cmake -S . -B build -G Ninja \
  -DCMAKE_C_COMPILER=/opt/rocm/llvm/bin/clang \
  -DCMAKE_CXX_COMPILER=/opt/rocm/llvm/bin/clang++ \
  -DCMAKE_CXX_FLAGS="-I/opt/rocm/include" \
  -DBUILD_SHARED_LIBS=ON -DGGML_BACKEND_DL=ON \
  -DGGML_HIP=ON -DGGML_CPU=OFF \
  -DGPU_TARGETS="${GPU_TARGETS}" \
  -DGGML_OPENMP=OFF -DGGML_CUDA_FORCE_CUBLAS=OFF -DGGML_RPC=ON \
  -DGGML_HIP_ROCWMMA_FATTN=OFF -DLLAMA_BUILD_BORINGSSL=ON \
  -DGGML_NATIVE=OFF -DGGML_STATIC=OFF \
  -DCMAKE_BUILD_TYPE=Release -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF \
  -DCMAKE_SYSTEM_NAME=Linux \
  -DCMAKE_HIP_FLAGS="-Wno-c++11-narrowing"
# ^ ROCm 6.1.2's __hip_bfloat16 is a plain aggregate (no float ctor), so
#   upstream mma.cuh's `nv_bfloat162 x[ne] = {{0.0f, 0.0f}}` is a narrowing
#   ERROR under the image's clang 17 (newer ROCm added the ctor, which is why
#   the TheRock ROCm 7 job compiles it fine). 0.0f -> 0 bits is the bf16 zero,
#   so suppressing the diagnostic is semantically safe. Note CMAKE_CXX_FLAGS
#   never reaches the HIP-language compiles of the .cu files; only
#   CMAKE_HIP_FLAGS does.

echo ">>> building"
cmake --build build --config Release -j"$(nproc)"

STAGE="${ROCM_STAGE:-/work/stage}"
mkdir -p "$STAGE"

echo ">>> staging HIP backend plugin"
cp -a build/bin/libggml-hip*.so* "$STAGE/" || { echo "libggml-hip backend not produced" >&2; ls -la build/bin/ | head; exit 1; }

echo ">>> bundling ROCm runtime deps of the backend"
# Auto-discover every ROCm runtime dep of the hip backend with ldd and copy
# the real file content under each SONAME name (no symlinks, so
# upload-artifact cannot triplicate them). Only /opt/rocm/* libs are bundled;
# system libs come from the target host.
ldd build/bin/libggml-hip*.so* | awk '/=> \// {print $1, $3}' | sort -u | \
while read -r soname path; do
  case "$path" in
    /opt/rocm/*) cp -aL "$path" "$STAGE/$soname" 2>/dev/null || true ;;
  esac
done

echo ">>> bundling rocBLAS / hipBLASLt kernels (data dirs, loaded at runtime next to their .so)"
# FILTERED to gfx90x: official ROCm ships kernels for every arch (9.2G
# combined), unlike TheRock's per-family dist. The arch-independent
# TensileLibrary*.dat fallbacks + manifests are required at runtime, so they
# are copied alongside the per-arch kernels. hipBLASLt 6.1.2 has no gfx906/
# gfx908 kernels at all — its dir only gains the gfx90a files.
mkdir -p "$STAGE/rocblas/library" "$STAGE/hipblaslt/library"
( cd /opt/rocm/lib/rocblas/library && \
  cp -an -- *gfx906* *gfx908* *gfx90a* TensileLibrary*.dat TensileManifest.txt \
     "$STAGE/rocblas/library/" ) 2>/dev/null || true
( cd /opt/rocm/lib/hipblaslt/library && \
  cp -an -- *gfx90a* TensileLibrary.dat TensileManifest.txt hipblasltExtOpLibrary.dat \
     "$STAGE/hipblaslt/library/" ) 2>/dev/null || true
echo "    rocblas gfx90x kernel files: $(find "$STAGE/rocblas/library" -name '*gfx90*' | wc -l)"

# sanity: gfx targets present in the backend fatbin (visible in the CI log)
strings build/bin/libggml-hip*.so* | grep -o 'gfx90[68a]' | sort -u || true

echo ">>> setting rpath \$ORIGIN on staged libs"
for f in "$STAGE"/*.so*; do
  [ -f "$f" ] && [ ! -L "$f" ] && patchelf --set-rpath '$ORIGIN' "$f" 2>/dev/null || true
done

echo ">>> staged ROCm-legacy backend:"
ls -la "$STAGE"
