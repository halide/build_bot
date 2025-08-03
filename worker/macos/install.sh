#!/usr/bin/env bash

set -eo pipefail

fail () {
  echo "$@"
  exit 1
}

BUILDBOT_ROOT=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )/../.." &> /dev/null && pwd)
cd "$BUILDBOT_ROOT"

##
# Check necessary tools are installed

if ! command -v brew > /dev/null 2>&1; then
  fail "Homebrew is not installed: cannot continue"
fi

##
# Install Homebrew dependencies

brew update
brew install ccache doxygen libjpeg libpng uv

##
# Configure ccache

ccache --set-config=sloppiness=pch_defines,time_macros
ccache -M 20G

##
# Install the autostart script

WORKER_SCRIPT="$(realpath "$BUILDBOT_ROOT/worker.sh")"
export WORKER_SCRIPT

awk '{
  line = $0
  while (match(line, /@[^@ \t\n\r]+@/)) {
    placeholder = substr(line, RSTART + 1, RLENGTH - 2)
    line = substr(line, 1, RSTART - 1) ENVIRON[placeholder] substr(line, RSTART + RLENGTH)
  }
  print line
}' worker/macos/org.halide-lang.buildbot.plist.in > "${PLIST}"
echo "Installed autostart config to ${PLIST}"

##
# Success!

echo "Finished! Restart your shell and run $WORKER_SCRIPT"
