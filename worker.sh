#!/usr/bin/env bash

# Early debug for launchd
if [ "$XPC_SERVICE_NAME" = "org.halide-lang.buildbot" ]; then
    echo "DEBUG: Script started, PATH=$PATH" >&2
fi

set -eo pipefail

fail () {
  echo "$@"
  exit 1
}

BUILDBOT_ROOT=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)
cd "$BUILDBOT_ROOT"

##
# Check necessary files are present

if [ ! -f worker/halide_bb_pass.txt ]; then
  fail "Missing worker/halide_bb_pass.txt: cannot continue"
fi

if [ -z "$HALIDE_BB_WORKER_NAME" ]; then
  fail "Environment variable HALIDE_BB_WORKER_NAME unset: cannot continue"
fi

if ! command -v uv > /dev/null 2>&1; then
  fail "uv is not installed: cannot continue"
fi

##
# Launch the worker

if [ "$XPC_SERVICE_NAME" = "org.halide-lang.buildbot" ]; then
    # Running under launchd - use foreground mode
    uv run --package worker buildbot-worker restart --nodaemon worker
else
    echo "Launching (or restarting) buildbot worker"
    uv run --package worker buildbot-worker restart worker
fi
