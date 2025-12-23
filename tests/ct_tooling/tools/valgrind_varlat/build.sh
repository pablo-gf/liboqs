#!/bin/bash
# SPDX-License-Identifier: MIT

echo "PATH in build.sh: $PATH"
command -v valgrind_varlat || echo "valgrind_varlat NOT FOUND"

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
    cmake -S .. -G Ninja -DCMAKE_C_FLAGS="$opt_flag" -DCMAKE_C_COMPILER=$compiler_version -DOQS_OPT_TARGET=$liboqs_build  -DCMAKE_BUILD_TYPE=Debug -DOQS_USE_OPENSSL=OFF -DOQS_DIST_BUILD=OFF -DOQS_ENABLE_TEST_CONSTANT_TIME=ON
    cmake --build . -j$(nproc)

    # Execute test.sh for both KEMs and SIGs
    cd $SCRIPT_DIR
    ./test.sh "$BUILD_DIR" kem $compiler_version $liboqs_build
    ./test.sh "$BUILD_DIR" sig $compiler_version $liboqs_build
}

# Read inputs from arguments
compiler_version=${1:?"Error: Compiler version argument is required."}
liboqs_build=${2:?"Error: liboqs build is required."}
opt_flag=${3:?"Error: Optimization flag argument is required."}

# Run the build and test process
build_and_test "$compiler_version" "$liboqs_build" "$opt_flag"