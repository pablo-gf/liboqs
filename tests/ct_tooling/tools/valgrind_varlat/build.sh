#!/bin/bash
# SPDX-License-Identifier: MIT

set -e

LIBOQS_DIR="/home/nics-lab/Escritorio/liboqs-ct-tooling/ct-tools/kyberslash/liboqs-ci-repl/liboqs"

# Iterate through the default and latest compiler versions
for compiler_version in gcc gcc-14 clang clang-20

    # Iterate through both liboqs builds: generic vs. optimized
    for liboqs_build in generic auto

        # Iterate through the different optimization flags (gcc uses -fno-tree-vectorize instead of -fno-vectorize)
        for opt_flag in -O0 -O1 -O2 -O3 -Os -Ofast "-O2 -fno-tree-vectorize" "-O3 -fno-tree-vectorize"; do
            
            BUILD_NAME=$(echo "$opt_flag"_"$compiler_version"_"$liboqs_build" | sed 's/^-//' | sed 's/ -/-/g')
            BUILD_DIR="$LIBOQS_DIR/build_$BUILD_NAME"
            
            # Build liboqs with the current opt_flag
            mkdir -p "$BUILD_DIR"
            cd "$BUILD_DIR"
            cmake -S .. -G Ninja -DCMAKE_C_FLAGS="$opt_flag" -DCMAKE_C_COMPILER=$compiler_version -DCMAKE_BUILD_TYPE=Debug -DOQS_USE_OPENSSL=OFF -DOQS_DIST_BUILD=OFF -DOQS_OPT_TARGET=$liboqs_build -DOQS_ENABLE_TEST_CONSTANT_TIME=ON
            cmake --build . -j$(nproc)

            # Execute on_liboqs.sh for both KEMs and SIGs
            cd ../..
            ./test.sh "$BUILD_DIR" kem $compiler_version $liboqs_build
            ./test.sh "$BUILD_DIR" sig $compiler_version $liboqs_build
        done
    done
done