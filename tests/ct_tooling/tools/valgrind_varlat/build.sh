#!/bin/bash
# SPDX-License-Identifier: MIT

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBOQS_DIR="$(realpath "$SCRIPT_DIR/../../../..")"

build_and_test() {
    local compiler_version=$1
    local liboqs_build=$2
    local opt_flag=$3

    BUILD_NAME=$(echo "valgrind_varlat${opt_flag//-/_}"_"$compiler_version"_"$liboqs_build" | sed 's/ -/-/g')
    BUILD_DIR="$LIBOQS_DIR/build_$BUILD_NAME"
    
    # Build liboqs with the current configuration
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    cmake -S .. -G Ninja -DCMAKE_C_FLAGS="$opt_flag" -DCMAKE_C_COMPILER=$compiler_version -DCMAKE_BUILD_TYPE=Debug -DOQS_USE_OPENSSL=OFF -DOQS_DIST_BUILD=OFF -DOQS_OPT_TARGET=$liboqs_build -DOQS_ENABLE_TEST_CONSTANT_TIME=ON
    cmake --build . -j$(nproc)

    # Execute test.sh for both KEMs and SIGs
    cd $SCRIPT_DIR
    ./test.sh "$BUILD_DIR" kem $compiler_version $liboqs_build
    ./test.sh "$BUILD_DIR" sig $compiler_version $liboqs_build
}

# Iterate through the default and latest compiler versions (temporally removing gcc-14 and clang-20  for workflow debugging)
for compiler_version in gcc  clang; do
    # Iterate through both liboqs builds: generic vs. optimized
    for liboqs_build in generic; do
        # Iterate through the different optimization flags (gcc uses -fno-tree-vectorize instead of -fno-vectorize) and execute tests asynchronously
        for opt_flag in -O0 -O1 -O2 -O3 -Os -Ofast "-O2 -fno-tree-vectorize" "-O3 -fno-tree-vectorize"; do
            build_and_test "$compiler_version" "$liboqs_build" "$opt_flag" &
        done
    done
done

# Wait for all background jobs to complete
wait