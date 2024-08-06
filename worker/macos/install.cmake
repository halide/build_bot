cmake_minimum_required(VERSION 3.28)

# Configure inputs
file(REAL_PATH "${CMAKE_CURRENT_LIST_DIR}/../.." BUILDBOT_ROOT)
file(REAL_PATH "~/.local/bin/halide_buildbot.sh" SCRIPT_PATH EXPAND_TILDE)

# Install launch script
message(STATUS "Installing ${SCRIPT_PATH}")
configure_file(
    "${CMAKE_CURRENT_LIST_DIR}/halide_buildbot.sh.in"
    "${SCRIPT_PATH}"
    FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
    @ONLY
)

# Autostart launch script
file(REAL_PATH "~/Library/LaunchAgents/org.halide-lang.buildbot.plist" launch_agent EXPAND_TILDE)
message(STATUS "Installing ${launch_agent}")
configure_file(
    "${CMAKE_CURRENT_LIST_DIR}/org.halide-lang.buildbot.plist.in"
    "${launch_agent}"
    @ONLY
)
