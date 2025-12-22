#!/bin/bash
# SPDX-License-Identifier: MIT

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBOQS_DIR="$(realpath "$SCRIPT_DIR/../../../..")"

build_and_test() {

    local compiler_version=$1
    local liboqs_build=$2
    local opt_flag=$3

    BUILD_NAME=$(echo "memsan${opt_flag//-/_}"_"$compiler_version"_"$liboqs_build" | sed 's/ -/-/g')
    BUILD_DIR="$LIBOQS_DIR/build_$BUILD_NAME"

    # Create backup files of the original tests files
    mv "$LIBOQS_DIR/tests/CMakeLists.txt" "$LIBOQS_DIR/tests/CMakeLists.txt.bak"
    mv "$LIBOQS_DIR/tests/test_kem.c" "$LIBOQS_DIR/tests/test_kem.c.bak"
    mv "$LIBOQS_DIR/tests/test_sig.c" "$LIBOQS_DIR/tests/test_sig.c.bak"

    # Replace original tests/CMakeLists.txt, test_kem.c, and test_sig.txt for their "MemSan poisoned" version
    cp "$SCRIPT_DIR/CMakeLists.txt" "$LIBOQS_DIR/tests/CMakeLists.txt"
    cp "$SCRIPT_DIR/test_kem.c" "$LIBOQS_DIR/tests/test_kem.c"
    cp "$SCRIPT_DIR/test_sig.c" "$LIBOQS_DIR/tests/test_sig.c"
    cp "$SCRIPT_DIR/rng_poison_memsan.c" "$LIBOQS_DIR/tests/rng_poison_memsan.c"

    # Build liboqs with the current configuration
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    cmake -S .. -G Ninja -DBUILD_SHARED_LIBS=ON -DCMAKE_C_COMPILER=$compiler_version -DCMAKE_BUILD_TYPE=Debug -DOQS_USE_OPENSSL=OFF -DOQS_DIST_BUILD=OFF -DOQS_OPT_TARGET=$liboqs_build -DCMAKE_C_FLAGS="-fsanitize=memory -fsanitize-recover=all $opt_flag -g" -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=memory" -DCMAKE_SHARED_LINKER_FLAGS="-fsanitize=memory"
    cmake --build . -j$(nproc)

    # Restore the original test files with the backups
    mv "$LIBOQS_DIR/tests/CMakeLists.txt.bak" "$LIBOQS_DIR/tests/CMakeLists.txt"
    mv "$LIBOQS_DIR/tests/test_kem.c.bak" "$LIBOQS_DIR/tests/test_kem.c"
    mv "$LIBOQS_DIR/tests/test_sig.c.bak" "$LIBOQS_DIR/tests/test_sig.c"
    rm "$LIBOQS_DIR/tests/rng_poison_memsan.c"

    # Execute test.sh for both KEMs and SIGs
    cd $SCRIPT_DIR
    ./test.sh "$BUILD_DIR" kem $compiler_version $liboqs_build
    ./test.sh "$BUILD_DIR" sig $compiler_version $liboqs_build
}

# Define a cleanup function that will restore the original test files with the backups
cleanup() {
    echo "Restoring original test files..."
    mv "$LIBOQS_DIR/tests/CMakeLists.txt.bak" "$LIBOQS_DIR/tests/CMakeLists.txt" 2>/dev/null || true
    mv "$LIBOQS_DIR/tests/test_kem.c.bak" "$LIBOQS_DIR/tests/test_kem.c" 2>/dev/null || true
    mv "$LIBOQS_DIR/tests/test_sig.c.bak" "$LIBOQS_DIR/tests/test_sig.c" 2>/dev/null || true
    rm "$LIBOQS_DIR/tests/rng_poison_memsan.c" 2>/dev/null || true
}

# Set the trap to call cleanup on EXIT or INT (Ctrl+C)
trap cleanup EXIT INT

# Iterate through the default and latest compiler versions (temporally removing and clang-20  for workflow debugging)
for compiler_version in clang; do
    # Iterate through both liboqs builds: generic vs. optimized
    for liboqs_build in generic; do
        # Iterate through the different optimization flags and execute tests asynchronously
        for opt_flag in  -O0 -O1 -O2 -O3 -Os -Ofast "-O2 -fno-vectorize" "-O3 -fno-vectorize"; do
            build_and_test "$compiler_version" "$liboqs_build" "$opt_flag" &
        done
    done
done

# Wait for all background jobs to complete
wait