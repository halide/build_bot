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

secrets_dir="${HALIDE_BB_SECRETS_DIR:-secrets}"
for secret in github_token buildbot_www_pass halide_bb_pass webhook_token; do
  if [ ! -s "$secrets_dir/${secret}.txt" ]; then
    fail "Missing or empty $secrets_dir/${secret}.txt: cannot continue"
  fi
done

if ! command -v uv >/dev/null 2>&1; then
  fail "uv is not installed: cannot continue"
fi

##
# Run the master

echo "Running buildbot $command master"
uv run --package master buildbot "$command" "$@" master