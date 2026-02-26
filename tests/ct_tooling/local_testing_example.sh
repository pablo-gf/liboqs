#!/bin/bash
# SPDX-License-Identifier: MIT

# This script iterates through the compilation options provided by the framework to execute constant time tests
# Adjust valgrind-varlat/memsan accordingly (note that gcc uses -fno-tree-vectorize while clang uses -fno-vectorize)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Iterate through the default and latest compiler versions
for compiler_version in gcc gcc-14 clang clang-20; do
    # Iterate through both liboqs builds: generic vs. optimized
    for liboqs_build in generic auto; do
        # Iterate through the different optimization flags and execute tests asynchronously
        for opt_flag in -O0 -O1 -O2 -O3 -Os -Ofast "-O2 -fno-tree-vectorize" "-O3 -fno-tree-vectorize"; do
            ./ct_test.sh valgrind-varlat "$compiler_version" "$liboqs_build" "$opt_flag" all
        done
    done
done