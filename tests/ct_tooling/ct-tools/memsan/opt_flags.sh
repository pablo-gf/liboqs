#!/bin/bash

set -e

SCRIPT_DIR="$(cd \"$(dirname \"${BASH_SOURCE[0]}\")\" && pwd)"
LIBOQS_DIR="$(realpath \"$SCRIPT_DIR/../../../../../../liboqs\")"

# Iterate through the default and latest compiler versions
for compiler_version in clang clang-20

    # Iterate through both liboqs builds: generic vs. optimized
    for libqos_build in generic auto

        # Iterate through the different optimization flags
        for opt_flag in  -O0 -O1 -O2 -O3 -Os -Ofast "-O2 -fno-vectorize" "-O3 -fno-vectorize"; do
            
            BUILD_NAME=$(echo "$opt_flag" | sed 's/^-//' | sed 's/ -/-/g')
            BUILD_DIR="$LIBOQS_DIR/build_$BUILD_NAME"
            
            # Build liboqs with the current opt flag into build_opt_flag
            mkdir -p "$BUILD_DIR"
            cd "$BUILD_DIR"
            cmake -S .. -G Ninja -DBUILD_SHARED_LIBS=ON -DCMAKE_C_COMPILER=$compiler_version -DCMAKE_BUILD_TYPE=Debug -DOQS_USE_OPENSSL=OFF -DOQS_DIST_BUILD=OFF -DOQS_OPT_TARGET=$liboqs_build -DCMAKE_C_FLAGS="-fsanitize=memory -fsanitize-recover=all $opt_flag -g" -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=memory" -DCMAKE_SHARED_LINKER_FLAGS="-fsanitize=memory"
            cmake --build . -j$(nproc)

            # Execute on_liboqs.sh for both KEMs and SIGs
            cd ../..
            ./on_liboqs.sh "$BUILD_DIR" kem $compiler_version $liboqs_build
            ./on_liboqs.sh "$BUILD_DIR" sig $compiler_version $liboqs_build
        done
    done
done