#!/bin/bash
#
# Windows Python prepends a Windows-style path when you activate a venv;
# this is fine in cmd.exe but confuses CMake greatly in git-bash.
# Dance on PATH to fix this.
#
# Note: execute via `source activate_windows_venv.sh`, not by running directly.
#
. venv/Scripts/activate
PATH=$(echo "$PATH" | sed 's,^\([C-Gc-g]\):\\,/\1/,g' | sed 's,:\([C-Gc-g]\):\\,/\1/,g')
export PATH
