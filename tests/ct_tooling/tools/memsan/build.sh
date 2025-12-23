#!/bin/bash
# SPDX-License-Identifier: MIT

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBOQS_DIR="$(realpath "$SCRIPT_DIR/../../../..")"

build_and_test() {
    local compiler_version=$1
    local liboqs_build=$2
    local opt_flag=$3
    local algorithm=$4

    BUILD_NAME=$(echo "valgrind_varlat_$algorithm${opt_flag//-/_}"_"$compiler_version"_"$liboqs_build" | sed 's/ -/-/g')
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
    cmake -S .. -G Ninja -DBUILD_SHARED_LIBS=ON -DCMAKE_C_COMPILER=$compiler_version -DOQS_OPT_TARGET=$liboqs_build -DCMAKE_BUILD_TYPE=Debug -DOQS_USE_OPENSSL=OFF -DOQS_DIST_BUILD=OFF -DOQS_ENABLE_TEST_CONSTANT_TIME=ON -DCMAKE_C_FLAGS="-fsanitize=memory -fsanitize-recover=all $opt_flag -g" -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=memory" -DCMAKE_SHARED_LINKER_FLAGS="-fsanitize=memory"
    cmake --build . -j$(nproc)

    # Restore the original test files with the backups
    mv "$LIBOQS_DIR/tests/CMakeLists.txt.bak" "$LIBOQS_DIR/tests/CMakeLists.txt"
    mv "$LIBOQS_DIR/tests/test_kem.c.bak" "$LIBOQS_DIR/tests/test_kem.c"
    mv "$LIBOQS_DIR/tests/test_sig.c.bak" "$LIBOQS_DIR/tests/test_sig.c"
    rm "$LIBOQS_DIR/tests/rng_poison_memsan.c"

    # Execute test.sh for both KEMs and SIGs
    cd $SCRIPT_DIR
    ./test.sh "$BUILD_DIR" $compiler_version $liboqs_build $algorithm
}

# Read inputs from arguments
compiler_version=${1:?"Error: Compiler version argument is required."}
liboqs_build=${2:?"Error: liboqs build is required."}
opt_flag=${3:?"Error: Optimization flag argument is required."}
algorithm=${4:?"Error: Algorithm is required."}

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

# Run the build and test process
build_and_test "$compiler_version" "$liboqs_build" "$opt_flag" "$algorithm"