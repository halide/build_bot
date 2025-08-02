#!/usr/bin/env bash

set -eo pipefail

BUILDBOT_ROOT=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)
cd "$BUILDBOT_ROOT"

if [ ! -f worker/halide_bb_pass.txt ]; then
  echo "Missing worker/halide_bb_pass.txt: cannot continue"
  exit 1
fi

if [ -z "$HALIDE_BB_MASTER_ADDR" ]; then
  echo "Environment variable HALIDE_BB_MASTER_ADDR unset: cannot continue"
  exit 1
fi

if [ -z "$HALIDE_BB_MASTER_PORT" ]; then
  echo "Environment variable HALIDE_BB_MASTER_PORT unset: cannot continue"
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
  echo "Installing worker launch scripts"
  cmake -P worker/macos/install.cmake

  echo "Starting buildbot"
  ~/.local/bin/halide_buildbot.sh
else
  echo "$(uname) not supported"
  exit 1
fi