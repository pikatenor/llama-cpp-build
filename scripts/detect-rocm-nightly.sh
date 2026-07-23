#!/usr/bin/env bash
# Detect the latest (or a pinned) TheRock ROCm nightly tarball for a given gfx
# target and print its download URL and version.
#
# Ported from lemonade-sdk/llamacpp-rocm. The multi-arch tarball index is a
# static HTML page with an embedded JSON `files` array (name + mtime); we parse
# that and pick the newest build by the YYYYMMDD date in the filename.
#
# Usage:
#   ./detect-rocm-nightly.sh --target gfx110X-all [--version latest|<ver>]
#
# Prints two lines to stdout:
#   line 1: full tarball URL
#   line 2: ROCm version string (e.g. 7.x.xaYYYYMMDD)
set -euo pipefail

target=""
version="latest"
while [ $# -gt 0 ]; do
  case "$1" in
    --target)  target="$2";  shift 2;;
    --version) version="$2"; shift 2;;
    -h|--help)
      sed -n '2,16p' "$0"; exit 0;;
    *) echo "unknown argument: $1" >&2; exit 2;;
  esac
done

[ -n "$target" ] || { echo "--target is required (e.g. gfx110X-all)" >&2; exit 2; }

base_url="https://rocm.nightlies.amd.com/tarball-multi-arch"

if [ "$version" = "latest" ]; then
  prefix="therock-dist-linux-${target}-"
  files_json=$(curl -s "$base_url/" | tr '\n' ' ' | grep -oP 'const files = \K\[.*?\](?=\s*;)')
  [ -n "$files_json" ] || { echo "Failed to parse file index from $base_url/" >&2; exit 1; }

  # Newest by the YYYYMMDD build date embedded in the filename. The anchored
  # regex excludes "-tests-" variants that share the same prefix/date.
  latest_file=$(echo "$files_json" | jq -r --arg p "$prefix" \
    '[.[] | select(.name | test("^" + $p + "[0-9]+\\.[0-9]+\\.[0-9]+(a|rc)[0-9]+\\.tar\\.gz$"))]
     | sort_by(.name | capture("(?<d>[0-9]{8})\\.tar\\.gz$").d)
     | last | .name // empty')
  [ -n "$latest_file" ] || { echo "No tarball found for prefix '$prefix' at $base_url/" >&2; exit 1; }

  if [[ "$latest_file" =~ therock-dist-linux-${target}-([0-9]+\.[0-9]+\.[0-9]+(a|rc)[0-9]+)\.tar\.gz ]]; then
    version="${BASH_REMATCH[1]}"
  else
    echo "Failed to extract ROCm version from: $latest_file" >&2; exit 1
  fi
  url="$base_url/$latest_file"
else
  url="$base_url/therock-dist-linux-${target}-${version}.tar.gz"
fi

echo "$url"
echo "$version"
