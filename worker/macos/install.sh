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
brew install --quiet ccache doxygen gettext libjpeg libpng node@18 protobuf uv

##
# Configure ccache

ccache --set-config=sloppiness=pch_defines,time_macros
ccache -M 20G

##
# Detect Dawn dependency

# TODO: this needs to be removed when WebGPU support is brought up to date with
#   upstream Dawn and https://github.com/halide/Halide/pull/8714 can be merged.
#   See also: https://github.com/halide/build_bot/issues/311

echo "Persisting WASM/WGPU environment to launchd agent..."

if [ -z "$HL_WEBGPU_NODE_BINDINGS" ]; then
  fail "Environment variable HL_WEBGPU_NODE_BINDINGS unset: cannot continue"
fi
export HL_WEBGPU_NODE_BINDINGS

if [ -z "$HL_WEBGPU_NATIVE_LIB" ]; then
  fail "Environment variable HL_WEBGPU_NATIVE_LIB unset: cannot continue"
fi
export HL_WEBGPU_NATIVE_LIB

if [ -z "$EMSDK" ]; then
  fail "Environment variable EMSDK unset: cannot continue"
fi
export EMSDK

# TODO: this should be managed in-repo
HALIDE_NODE_JS_PATH="$(brew --prefix node@18)/bin/node"
export HALIDE_NODE_JS_PATH

##
# Install the autostart script

PLIST="$(realpath ~/Library/LaunchAgents)/org.halide-lang.buildbot.plist"

WORKER_SCRIPT="$(realpath "$BUILDBOT_ROOT/worker.sh")"
export WORKER_SCRIPT

if [ -z "$HALIDE_BB_WORKER_NAME" ]; then
  fail "Environment variable HALIDE_BB_WORKER_NAME unset: cannot continue"
fi
export HALIDE_BB_WORKER_NAME

LAUNCHD_PATH="$(brew --prefix)/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export LAUNCHD_PATH

envsubst < worker/macos/org.halide-lang.buildbot.plist.in > "${PLIST}"

plutil -lint "${PLIST}" || fail "Generated plist is invalid"

launchctl unload "${PLIST}" 2>/dev/null || true  # Remove if already loaded
launchctl load "${PLIST}"

echo "Installed and loaded autostart service"

##
# Success!

echo "Finished! The buildbot worker is now running and will start automatically on login."
