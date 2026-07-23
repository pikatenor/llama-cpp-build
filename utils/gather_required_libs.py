#!/usr/bin/env python3
"""Gather the ROCm shared libraries that llama-server needs at runtime.

Run llama-server from --dest-dir, parse "error while loading shared libraries"
errors, walk --rocm-dir to find each missing .so, copy it next to the binary,
and repeat until no more are missing. Use this to regenerate the bundled ROCm
library list in the build workflow when ROCm or llama.cpp artifacts change.

Originally from lemonade-sdk/llamacpp-rocm.
"""

import subprocess
import os
import shutil
import argparse


def find_lib_in_rocm(libname, rocm_dir):
    for root, _, files in os.walk(rocm_dir):
        if libname in files:
            return os.path.join(root, libname)
    raise RuntimeError(f"Could not find {libname} in {rocm_dir}")


def main():
    parser = argparse.ArgumentParser(
        description="Gather required libraries for llama-server"
    )
    parser.add_argument(
        "--rocm-dir",
        default="/opt/rocm",
        help="Path to ROCm installation directory (default: /opt/rocm)",
    )
    parser.add_argument(
        "--dest-dir",
        default=os.path.expanduser("~/llama.cpp/build/bin"),
        help="Destination directory for libraries and binary (default: ~/llama.cpp/build/bin)",
    )

    args = parser.parse_args()

    rocm_dir = args.rocm_dir
    dest_dir = args.dest_dir
    binary = os.path.join(dest_dir, "llama-server")

    os.makedirs(dest_dir, exist_ok=True)
    result = subprocess.run([binary], capture_output=True, text=True)
    print(f"Error Found: {result.stderr}")

    while "error while loading shared libraries" in result.stderr:
        so_file = result.stderr.split("shared libraries: ")[1].split(": ")[0]
        so_file_path = find_lib_in_rocm(so_file, rocm_dir)
        shutil.copy2(so_file_path, dest_dir)
        print(f"Copied {so_file_path} -> {dest_dir}")
        result = subprocess.run([binary], capture_output=True, text=True)
        print(f"Error Found: {result.stderr}")


if __name__ == "__main__":
    main()
