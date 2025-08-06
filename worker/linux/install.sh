#!/usr/bin/env bash

set -eo pipefail

fail () {
  echo "$@"
  exit 1
}

BUILDBOT_ROOT=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )/../.." &> /dev/null && pwd)
cd "$BUILDBOT_ROOT"

##
# Check necessary environment variables

if [ -z "$HALIDE_BB_WORKER_NAME" ]; then
  fail "Environment variable HALIDE_BB_WORKER_NAME unset: cannot continue"
fi

##
# Update package lists and install system dependencies

echo "Updating package lists..."
sudo apt update

echo "Installing system dependencies..."
sudo apt install -y \
    build-essential \
    ccache \
    cmake \
    doxygen \
    gettext \
    git \
    libjpeg-dev \
    libpng-dev \
    libprotobuf-dev \
    pipx \
    protobuf-compiler \
    python3-dev

##
# Install uv via pipx

echo "Installing uv via pipx..."
pipx install uv

# Ensure pipx binaries are in PATH
export PATH="$HOME/.local/bin:$PATH"

if ! command -v uv > /dev/null 2>&1; then
  fail "uv installation failed or not in PATH"
fi

##
# Configure ccache

ccache --set-config=sloppiness=pch_defines,time_macros
ccache -M 20G

##
# Install the systemd service

WORKER_SCRIPT="$(realpath "$BUILDBOT_ROOT/worker.sh")"
SERVICE_FILE="/tmp/halide-buildbot-worker.service"

# Generate the service file from template  
export WORKER_SCRIPT
export HALIDE_BB_WORKER_NAME
export USER
export HOME
export BUILDBOT_ROOT
envsubst < worker/linux/halide-buildbot-worker.service.in > "$SERVICE_FILE"

# Install the service
sudo cp "$SERVICE_FILE" /etc/systemd/system/halide-buildbot-worker.service
sudo systemctl daemon-reload

# Stop any existing service
sudo systemctl stop halide-buildbot-worker 2>/dev/null || true

# Enable and start the service
sudo systemctl enable halide-buildbot-worker
sudo systemctl start halide-buildbot-worker

echo "Enabled and started systemd service"

# Clean up temp file
rm "$SERVICE_FILE"

##
# Success!

echo "Finished! The buildbot worker is now running and will start automatically at boot."