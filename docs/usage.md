# 実行時の使い方・バックエンド切替

## 概要

配布 tarball には 1 つの `llama-server`（と各種ツール）と、複数のバックエンド
`libggml-*.so`（CUDA / ROCm / Vulkan / CPU）が含まれる。ggml は **実行ファイルと同じ
ディレクトリ**（既定の探索パス）にあるバックエンドを起動時に自動ロードする。

複数バックエンドを同時にロードすることも可能で、`--list-devices` で一覧表示、
`--device <name>` でデバイスを指定できる。CUDA と ROCm が両方存在するマシンでは、
実行時にどちらを使うかを選べる。

## run.sh による切替（推奨）

`run.sh <vendor> [llama-server の引数...]` は、選んだベンダのバックエンド `.so` のみを
`bin/` に見せてから `llama-server` を起動するラッパ。これにより GPU 種別ごとに
クリーンに使い分けられる。

```sh
./run.sh cuda    -m model.gguf -ngl 99 -p "hello"     # NVIDIA GPU
./run.sh rocm    -m model.gguf -ngl 99 -p "hello"     # AMD gfx110x
./run.sh vulkan  -m model.gguf -ngl 99 -p "hello"     # Vulkan 対応 GPU
./run.sh all     -m model.gguf -ngl 99                # bin/ の既定（CPU + 追加済みバックエンド）
```

`run.sh` が行うこと:
1. `bin/` から一旦 CUDA/ROCm/Vulkan バックエンドの symlink を削除
2. 選んだベンダの `backends/<vendor>/libggml-*.so` を `bin/` に symlink
3. `LD_LIBRARY_PATH` に `backends/<vendor>` を追加（バックエンド `.so` が同梱ランタイムを見つけるため）
4. `bin/llama-server` を `exec`

## 手動でのバックエンド指定（GGML_BACKEND_PATH）

llama.cpp 本体の機構を直接使うこともできる。環境変数 `GGML_BACKEND_PATH` で
out-of-tree バックエンドを追加ロードできる（バージョンにより単一 `.so` ファイル指定。
詳しくは該当版の `ggml/src/ggml-backend-reg.cpp` を参照）。

```sh
# 例: ROCm バックエンドを明示ロード
export LD_LIBRARY_PATH="$PWD/backends/rocm:$LD_LIBRARY_PATH"
export GGML_BACKEND_PATH="$PWD/backends/rocm/libggml-hip-*.so"
./bin/llama-server -m model.gguf -ngl 99 --list-devices
```

## デバイス一覧・指定

```sh
./run.sh all --list-devices        # 例: cuda0, hip0, vulkan0, cpu の一覧
./run.sh all -m model.gguf --device vulkan0 -ngl 99
```

`--device none` で GPU を完全に無効化（CPU のみ）することも可能。

## トラブルシューティング

- **バックエンドがロードされない**: `bin/` に `libggml-*.so` が見えるか確認。
  `ldd ./bin/llama-server` で解決できないシンボルがないか確認。
- **ROCm 版が動かない**: AMD GPU ドライバ/`amdgpu` が実行機に必要（ROCm **ランタイム**は同梱、
  ドライバは別）。gfx が合っているか確認（`rocminfo | grep gfx`）。
- **CUDA 版が動かない**: NVIDIA ドライバが必要（CUDA **ランタイム**は同梱、ドライバは別）。
  CC がビルド対象に含まれているか確認。
- **Vulkan 版が動かない**: Vulkan 対応ドライバ（ICD）が実行機に必要。`vulkaninfo` で確認。
