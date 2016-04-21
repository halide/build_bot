#!/bin/bash

# Deletes builds where a newer one exists. The first line finds all
# the build names (e.g. halide-mac-64-trunk) by stripping out the
# commit hash. The second line lists all but the newest of each build
# prefix. The third line deletes them.

for suffix in zip tgz; do
    ls halide-*.${suffix} | sed "s/-[^-]*.${suffix}//" | sort | uniq | \
        while read B; do ls -t ${B}*.${suffix} | tail -n +5; done | \
        while read F; do rm ${F}; done
done
