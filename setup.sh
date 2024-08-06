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

create_venv () {
  (
    python3 -m venv venv
    source venv/bin/activate
    python3 -m pip install -U pip setuptools[core] wheel
    python3 -m pip install -r requirements.txt
  )
}

if [ "$(uname)" == "Darwin" ]; then
  echo "Creating virtual environment"
  test -d venv || create_venv

  echo "Installing worker launch scripts"
  cmake -P worker/macos/install.cmake

  echo "Starting buildbot"
  ~/.local/bin/halide_buildbot.sh
else
  echo "$(uname) not supported"
  exit 1
fi