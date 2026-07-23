#!/usr/bin/env bash
# Free disk space on a GitHub-hosted Ubuntu runner before a heavy build.
# Adapted from ai-dock/llama.cpp-cuda "Maximize build space" step.
# Safe to run on any Ubuntu runner; missing tools/steps are skipped.
set -uo pipefail

echo "=== Initial Disk Space ==="
df -h /

echo "=== Removing unnecessary packages ==="
sudo apt-get remove -y '^aspnetcore-.*' || true
sudo apt-get remove -y '^dotnet-.*' --fix-missing || true
sudo apt-get remove -y '^llvm-.*' --fix-missing || true
sudo apt-get remove -y 'php.*' --fix-missing || true
sudo apt-get remove -y '^mongodb-.*' --fix-missing || true
sudo apt-get remove -y '^mysql-.*' --fix-missing || true
sudo apt-get remove -y azure-cli google-chrome-stable firefox powershell mono-devel libgl1-mesa-dri --fix-missing || true
sudo apt-get autoremove -y || true
sudo apt-get clean || true

echo "=== Removing large directories ==="
sudo rm -rf /usr/share/dotnet \
            /usr/local/lib/android \
            /opt/ghc \
            /opt/hostedtoolcache/CodeQL \
            /usr/local/share/boost \
            /usr/share/swift \
            /usr/local/.ghcup \
            "${AGENT_TOOLSDIRECTORY:-}" 2>/dev/null || true

if command -v docker >/dev/null 2>&1; then
  echo "=== Pruning Docker ==="
  docker system prune -af || true
fi

echo "=== After Cleanup ==="
df -h /
