#!/usr/bin/env bash

set -eo pipefail

fail () {
  echo "$@"
  exit 1
}

BUILDBOT_ROOT=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)
cd "$BUILDBOT_ROOT"

##
# Determine the command to give to the master

if [[ $# -eq 1 ]]; then
  command="$1"
elif [[ $# -gt 1 ]]; then
  echo "Usage: $0 [command]" >&2
  exit 1
elif [[ -f master/twistd.pid ]]; then
  command="reconfig"
else
  command="start"
fi

##
# Check necessary files are present

if [ ! -f master/github_token.txt ]; then
  fail "Missing master/github_token.txt: cannot continue"
fi

if [ ! -f master/buildbot_www_pass.txt ]; then
  fail "Missing master/buildbot_www_pass.txt: cannot continue"
fi

if [ ! -f master/halide_bb_pass.txt ]; then
  fail "Missing master/halide_bb_pass.txt: cannot continue"
fi

if [ ! -f master/webhook_token.txt ]; then
  fail "Missing master/webhook_token.txt: cannot continue"
fi

if ! command -v uv > /dev/null 2>&1; then
  fail "uv is not installed: cannot continue"
fi

##
# Run the master

echo "Running buildbot $command master"
uv run --package master buildbot "$command" master
