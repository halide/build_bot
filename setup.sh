#!/usr/bin/env bash

set -eo pipefail

BUILDBOT_ROOT=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)
cd "$BUILDBOT_ROOT"

if [ ! -f worker/halide_bb_pass.txt ]; then
  echo "Missing worker/halide_bb_pass.txt: cannot continue"
  exit 1
fi

if [ -z "$HALIDE_BB_WORKER_NAME" ]; then
  echo "Environment variable HALIDE_BB_WORKER_NAME unset: cannot continue"
  exit 1
fi

if ! command -v uv > /dev/null 2>&1; then
  echo "uv is not installed: cannot continue"
  exit 1
fi

if [ "$(uname)" == "Darwin" ]; then
  echo "Installing macOS startup launch scripts"
  uv run --extra worker --no-dev cmake -P worker/macos/install.cmake
fi

echo "Launching (or restarting) buildbot worker"
uv run --extra worker --no-dev buildbot-worker restart worker
