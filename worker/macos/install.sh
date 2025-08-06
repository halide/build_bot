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
brew install ccache doxygen gettext libjpeg libpng protobuf uv

##
# Configure ccache

ccache --set-config=sloppiness=pch_defines,time_macros
ccache -M 20G

##
# Install the autostart script

PLIST="$(realpath ~/Library/LaunchAgents)/org.halide-lang.buildbot.plist"

WORKER_SCRIPT="$(realpath "$BUILDBOT_ROOT/worker.sh")"
export WORKER_SCRIPT

if [ -z "$HALIDE_BB_WORKER_NAME" ]; then
  fail "Environment variable HALIDE_BB_WORKER_NAME unset: cannot continue"
fi
export HALIDE_BB_WORKER_NAME

envsubst < worker/macos/org.halide-lang.buildbot.plist.in > "${PLIST}"

plutil -lint "${PLIST}" || fail "Generated plist is invalid"

launchctl unload "${PLIST}" 2>/dev/null || true  # Remove if already loaded
launchctl load "${PLIST}"

echo "Installed and loaded autostart service"

##
# Success!

echo "Finished! The buildbot worker is now running and will start automatically on login."
