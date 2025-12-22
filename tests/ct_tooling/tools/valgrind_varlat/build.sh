#!/bin/bash
# SPDX-License-Identifier: MIT

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBOQS_DIR="$(realpath "$SCRIPT_DIR/../../../..")"

build_and_test() {
    local compiler_version=$1
    local opt_flag=$2

    BUILD_NAME=$(echo "valgrind_varlat${opt_flag//-/_}"_"$compiler_version" | sed 's/ -/-/g')
    BUILD_DIR="$LIBOQS_DIR/build_$BUILD_NAME"
    
    # Build liboqs with the current configuration
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    cmake -S .. -G Ninja -DCMAKE_C_FLAGS="$opt_flag" -DCMAKE_C_COMPILER=$compiler_version -DCMAKE_BUILD_TYPE=Debug -DOQS_USE_OPENSSL=OFF -DOQS_DIST_BUILD=OFF -DOQS_ENABLE_TEST_CONSTANT_TIME=ON
    cmake --build . -j$(nproc)

    # Execute test.sh for both KEMs and SIGs
    cd $SCRIPT_DIR
    ./test.sh "$BUILD_DIR" kem $compiler_version
    ./test.sh "$BUILD_DIR" sig $compiler_version
}

# Read inputs from arguments
compiler_version=${1:?"Error: Compiler version argument is required."}
opt_flag=${2:?"Error: Optimization flag argument is required."}

# Run the build and test process
build_and_test "$compiler_version" "$opt_flag"