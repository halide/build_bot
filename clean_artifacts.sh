#!/bin/bash

# Deletes builds where a newer one exists. The first line finds all
# the build names (e.g. halide-mac-64-trunk) by stripping out the
# commit hash. The second line lists all but the newest of each build
# prefix. The third line deletes them.

ls halide-*.tgz | sed "s/-[^-]*.tgz//" | sort | uniq | \
while read B; do ls -t ${B}*.tgz | tail -n +3; done | \
while read F; do rm ${F}; done