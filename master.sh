#!/usr/bin/env bash

set -eo pipefail

fail() {
  echo "$@" >&2
  exit 1
}

BUILDBOT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
cd "$BUILDBOT_ROOT"

##
# Determine the command to give to the master

command="${1:-}"
shift || true

if [[ -z "$command" ]]; then
  if [[ -f master/twistd.pid ]]; then
    command="reconfig"
  else
    command="start"
  fi
fi

##
# Check necessary files are present

if [ ! -s secrets/github_token.txt ]; then
  fail "Missing or empty secrets/github_token.txt: cannot continue"
fi

if [ ! -s secrets/buildbot_www_pass.txt ]; then
  fail "Missing or empty secrets/buildbot_www_pass.txt: cannot continue"
fi

if [ ! -s secrets/halide_bb_pass.txt ]; then
  fail "Missing or empty secrets/halide_bb_pass.txt: cannot continue"
fi

if [ ! -s secrets/webhook_token.txt ]; then
  fail "Missing or empty secrets/webhook_token.txt: cannot continue"
fi

if ! command -v uv >/dev/null 2>&1; then
  fail "uv is not installed: cannot continue"
fi

##
# Run the master

echo "Running buildbot $command master"
uv run --package master buildbot "$command" "$@" master