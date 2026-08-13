# Personal multi-backend llama.cpp build

## Target

| Backend | Toolchain | Targets |
|---|---|---|
| CUDA 12.8.1 | `nvidia/cuda:12.8.1-cudnn-devel-ubuntu22.04` Docker | sm50 / 52 / 75 / 80 / 86 / 89 / 90 / 100 / 120 |
| ROCm 7 (gfx110x) | TheRock nightly | gfx1100 / gfx1101 / gfx1102 / gfx1103 |
| Vulkan | Vulkan SDK | (ICD provided by the host GPU driver) |
| CPU | gcc/clang | `GGML_CPU_ALL_VARIANTS` (runtime auto-selects the best SIMD) |

## Structure
```
llama-cpp-build-<tag>-linux-x64/
├── bin/                 # llama-server / llama-cli / ...  + libggml.so / libllama.so / libggml-cpu*.so
├── backends/
│   ├── cuda/            # libggml-cuda*.so  + CUDA runtime (cudart/cublas/...)
│   ├── rocm/            # libggml-hip*.so   + ROCm runtime + rocblas/hipblaslt kernel
│   └── vulkan/          # libggml-vulkan*.so + libvulkan.so*
├── run.sh
├── VERSION.txt
└── README.txt
```

## Usage

Each backend ships as a separate release asset (so no single file exceeds GitHub's 2 GiB limit). Download **base** plus the backend(s) you need and extract them into the same directory:

```sh
tar xzf llama-cpp-build-<tag>-base-linux-x64.tar.gz
tar xzf llama-cpp-build-<tag>-cuda-linux-x64.tar.gz    # NVIDIA
tar xzf llama-cpp-build-<tag>-rocm-linux-x64.tar.gz    # AMD gfx110x
tar xzf llama-cpp-build-<tag>-vulkan-linux-x64.tar.gz  # optional
cd llama-cpp-build-<tag>-linux-x64

# Start with the chosen backend (arguments are passed directly to llama-server)
./run.sh cuda    -m model.gguf -ngl 99        # NVIDIA
./run.sh rocm    -m model.gguf -ngl 99        # AMD gfx110x
./run.sh vulkan  -m model.gguf -ngl 99        # Vulkan-capable GPU
./run.sh all     --list-devices               # List available devices (defaults to CPU)

# You can also explicitly specify a device
./run.sh all     -m model.gguf --device cuda0 -ngl 99
```

`run.sh` only exposes the selected vendor backend .so files in bin/, relying on ggml's behavior of automatically loading backends located in the same directory as the executable.
See [docs/usage.md](docs/usage.md) for details.

## Build

The workflow `.github/workflows/build.yml` runs the following jobs:

```
resolve-version → build-base / build-cuda / build-rocm / build-vulkan → package → release
```

- Trigger: daily cron at 00:30 UTC, plus manual `workflow_dispatch` from the Actions tab
- Upstream: automatically follows the latest release tag of `ggml-org/llama.cpp`
- Releases are built and published only when a new upstream release is detected (use the `force_build` input to force a rebuild)

## Related projects & credits

Build procedure and scripts were reused from the following projects:
- [ai-dock/llama.cpp-cuda](https://github.com/ai-dock/llama.cpp-cuda) — CUDA Docker build
- [lemonade-sdk/llamacpp-rocm](https://github.com/lemonade-sdk/llamacpp-rocm) — TheRock ROCm + runtime bundling
- [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) — upstream (Georgi Gerganov / ggml-org)

`utils/gather_required_libs.py` is a helper to regenerate the bundled ROCm libraries (originated from lemonade-sdk).
