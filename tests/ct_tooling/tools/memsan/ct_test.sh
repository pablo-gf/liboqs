#!/bin/bash
# SPDX-License-Identifier: MIT

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBOQS_DIR="$(realpath "$SCRIPT_DIR/../../../..")"

# Build function
build() {
    local COMP_V=$1
    local LIBOQS_BUILD=$2
    local OPT_FLAG=$3
    local BUILD_DIR=$4
   
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
    echo "Building liboqs with -DCMAKE_C_COMPILER=$compiler_version -DOQS_OPT_TARGET=$liboqs_build and optimization flag=$opt_flag"
    cmake -S .. -G Ninja -DBUILD_SHARED_LIBS=ON -DCMAKE_C_COMPILER=$compiler_version -DCMAKE_BUILD_TYPE=Debug -DOQS_USE_OPENSSL=OFF -DOQS_DIST_BUILD=OFF -DOQS_OPT_TARGET=$liboqs_build -DCMAKE_C_FLAGS="-fsanitize=memory -fsanitize-recover=all $opt_flag -g" -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=memory" -DCMAKE_SHARED_LINKER_FLAGS="-fsanitize=memory" > /dev/null 2>&1 || true
    cmake --build . -j$(nproc) > /dev/null 2>&1 || true

    # Restore the original test files with the backups
    mv "$LIBOQS_DIR/tests/CMakeLists.txt.bak" "$LIBOQS_DIR/tests/CMakeLists.txt"
    mv "$LIBOQS_DIR/tests/test_kem.c.bak" "$LIBOQS_DIR/tests/test_kem.c"
    mv "$LIBOQS_DIR/tests/test_sig.c.bak" "$LIBOQS_DIR/tests/test_sig.c"
    rm "$LIBOQS_DIR/tests/rng_poison_memsan.c"
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

# Test function for individual algorithm testing
test() {
    local BUILD_DIR=$1
    local TEST_TYPE=$2
    local COMP_V=$3
    local LIBOQS_BUILD=$4
    local ALGORITHM=$5
    local SCRIPT_DIR=$6

    COMP_V="${COMP_V//-/_}" # Replace - with _

    # Set test binary depending on whether it is a KEM or SIG
    if [[ "$TEST_TYPE" == "kem" ]]; then
        TEST_BINARY="test_kem"
        UPPER_TYPE="KEM"
    elif [[ "$TEST_TYPE" == "sig" ]]; then
        TEST_BINARY="test_sig"
        UPPER_TYPE="SIG"
    fi

    # Extract optimization level from BUILD_DIR
    OPT_LEVEL=$(basename "$BUILD_DIR" | sed -E 's/.*-O([0-9a-zA-Z]+)(.*)/\1\2/' | sed 's/_/-/g')

    # Create log directory
    LOG_DIR="${SCRIPT_DIR}/logs/${COMP_V}_${LIBOQS_BUILD}"
    mkdir -p "$LOG_DIR"
    CURRENT_RUN_DIR="$LOG_DIR/${OPT_LEVEL}"
    mkdir -p "$CURRENT_RUN_DIR"

    # Create output directories
    OUTPUT_DIR="$CURRENT_RUN_DIR/$TEST_TYPE"
    mkdir -p "$OUTPUT_DIR"
    SUMMARY_FILE="$OUTPUT_DIR/${TEST_TYPE}_summary.txt"

    cd "$LIBOQS_DIR"

    # Retrieve MemSan compilation options from CMakeCache.txt
    MEMSAN_OPTIONS=$(grep "CMAKE_C_FLAGS:" "$BUILD_DIR/CMakeCache.txt" | cut -d'=' -f2-)

    # Extract the compiler path from CMakeCache.txt in each build
    COMPILER_PATH=$(grep -E '^CMAKE_C_COMPILER:.*=' "$BUILD_DIR"/CMakeCache.txt | head -n1 | cut -d'=' -f2- | tr -d '\r')
    COMPILER_VERSION=$("$COMPILER_PATH" --version 2>&1 | head -n1)

    # Extract system's architecture
    ARCH="$(uname -m)"

    MAX_WARNINGS=100000

    # Check if this is first algorithm (header only once)
    if [[ ! -s "$SUMMARY_FILE" ]]; then
        # FIRST algorithm: write full header
        {
            echo "========================================"
            echo "Compiled with: $MEMSAN_OPTIONS"
            echo "Compiler version: ${COMPILER_VERSION}"
            echo "Architecture: ${ARCH}"
            echo "========================================"
            echo ""
        } | tee "$SUMMARY_FILE"
    else
        # SUBSEQUENT algorithms: skip header, just separator
        echo "" | tee -a "$SUMMARY_FILE"
    fi

    PASS_COUNT=0
    FAIL_COUNT=0
   
    echo -n "Testing $UPPER_TYPE: $ALGORITHM ... " | tee -a "$SUMMARY_FILE"
    
    LOG_FILE="$OUTPUT_DIR/${ALGORITHM}_${TIMESTAMP}.log"
    touch "$LOG_FILE"

    # Only count and store unique summary lines
    # Exit early if warning count exceeds MAX_WARNINGS threshold
    "$BUILD_DIR"/tests/$TEST_BINARY "$algo" 2>&1 | awk -v log_file="$LOG_FILE" -v max_warnings="$MAX_WARNINGS" '
        /^SUMMARY: MemorySanitizer:/ {
            # Check if this exact SUMMARY was already logged and store it if not
            cmd = "grep -Fxq \"" $0 "\" " log_file
            if (system(cmd) != 0) {
                warnings++
                print >> log_file
                fflush(log_file)
            }

            if (warnings >= max_warnings) {
                print warnings > log_file ".count"
                print "TERMINATED: Exceeded " max_warnings " warnings" >> log_file
                fflush(log_file)
                terminated = 1
                exit 1
            }
        }
        # Count and store the number of unique warnings obtained and store it
        END {
            if (!terminated && warnings > 0) {
                print warnings > log_file ".count"
            } else if (!terminated) {
                print 0 > log_file ".count"
            }
        }
    '
    EXIT_CODE=$?

    # Retrieve the contents of the warnings count
    ERROR_COUNT=$(cat "$LOG_FILE.count" 2>/dev/null)
    ERROR_COUNT=${ERROR_COUNT:-0}

    if [ "$ERROR_COUNT" -eq "$MAX_WARNINGS" ]; then
        echo "FAIL" | tee -a "$SUMMARY_FILE"
        echo "  → Found $ERROR_COUNT warnings (warning cap reached — further warnings suppressed)" \
            | tee -a "$SUMMARY_FILE"
        ((++FAIL_COUNT))

    elif [ "$ERROR_COUNT" -gt 0 ]; then
        echo "FAIL" | tee -a "$SUMMARY_FILE"
        echo "  → Found $ERROR_COUNT warnings" \
            | tee -a "$SUMMARY_FILE"
        ((++FAIL_COUNT))

    elif [ $EXIT_CODE -ne 0 ]; then
        echo "FAIL (Exit code: $EXIT_CODE)" | tee -a "$SUMMARY_FILE"
        ((++FAIL_COUNT))

    else
        echo "PASS" | tee -a "$SUMMARY_FILE"
        ((++PASS_COUNT))

    fi

    rm -f "$OUTPUT_DIR"/*.log.count

    # echo "" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
    # echo "$UPPER_TYPE Results: $PASS_COUNT passed, $FAIL_COUNT failed" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
    # echo "" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
}

get_enabled_algs() {
    local ALG_TYPE="$1"
    local LIBOQS_DIR="$2"

    env | grep OQS || echo "NO OQS ENV FOUND"

    if [[ "$ALG_TYPE" == "kems" ]]; then
        KEMS=$(cd "$LIBOQS_DIR" && python3 -c "import sys
sys.path.insert(0, 'tests')
import helpers
for kem in helpers.available_kems_by_name():
    if helpers.is_kem_enabled_by_name(kem):
        print(kem)")
    elif [[ "$ALG_TYPE" == "sigs" ]]; then
        SIGS=$(cd "$LIBOQS_DIR" && python3 -c "import sys
sys.path.insert(0, 'tests')
import helpers
for sig in helpers.available_sigs_by_name():
    if helpers.is_sig_enabled_by_name(sig):
        print(sig)")
    fi
}

# Read inputs from arguments
if [ "$#" -lt 4 ]; then
    echo "Usage: $0 <compiler_version> <liboqs_build> <opt_flags...> <input>"
    echo "Example: $0 clang-20 generic -O2 -fno-tree-vectorize all"
    exit 1
fi

compiler_version="$1"
liboqs_build="$2"

# The last argument is the input (all/kems/sigs/<specific_variant>)
input="${!#}"

# Collect all optimization flags between position 3 and the last-1 argument
if [ "$#" -gt 3 ]; then
    num_opt_args=$(( $# - 3 ))
    opt_flag="${@:3:num_opt_args}"
else
    opt_flag=""
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBOQS_DIR="$(realpath "$SCRIPT_DIR/../../../..")"

# Sanitize opt flags for use in build directory name
sanitized_opt_flag=$(printf "%s" "$opt_flag" | tr ' ' '_' | tr -c '[:alnum:]_-' '_')
if [ -z "$sanitized_opt_flag" ]; then
    sanitized_opt_flag=default
fi

BUILD_NAME="valgrind_varlat_${sanitized_opt_flag}_${compiler_version}_${liboqs_build}"
BUILD_DIR="$LIBOQS_DIR/build_$BUILD_NAME"

# Build liboqs with the specified compilation parameters
build "$compiler_version" "$liboqs_build" "$opt_flag" "$BUILD_DIR"

# Export build dir for tests/helpers.py to find generated headers
cd "$LIBOQS_DIR"
export OQS_BUILD_DIR="$BUILD_DIR"

get_enabled_algs kems "$LIBOQS_DIR"
get_enabled_algs sigs "$LIBOQS_DIR"

# Find what the user wants to test
# Case 1: All algorithms
if [[ "$input" == "all" ]]; then
    for kem in $KEMS; do
        test "$BUILD_DIR" kem $compiler_version $liboqs_build "$kem" "$SCRIPT_DIR"
    done

    for sig in $SIGS; do
        # Skip SPHINCS and SLH-DSA for SIG tests
        if [[ "$sig" == *SPHINCS* || "$sig" == *SLH_DSA* ]]; then
            echo "Skipping $UPPER_TYPE $sig" | tee -a "$SUMMARY_FILE"
            continue
        fi
        test "$BUILD_DIR" sig $compiler_version $liboqs_build "$sig" "$SCRIPT_DIR"
    done

# Case 2: All KEMs
elif [[ "$input" == "kems" ]]; then
    for kem in $KEMS; do
        test "$BUILD_DIR" kem $compiler_version $liboqs_build "$kem" "$SCRIPT_DIR"
    done

# Case 3: All SIGS
elif [[ "$input" == "sigs" ]]; then
    for sig in $SIGS; do
        # Skip SPHINCS and SLH-DSA for SIG tests
        if [[ "$sig" == *SPHINCS* || "$sig" == *SLH_DSA* ]]; then
            echo "Skipping $UPPER_TYPE $sig" | tee -a "$SUMMARY_FILE"
            return 0
        fi
        test "$BUILD_DIR" sig $compiler_version $liboqs_build "$sig" "$SCRIPT_DIR"
    done

# Case 4: A specific KEM
elif echo "$KEMS" | grep -Fxq "$input"; then
        test "$BUILD_DIR" kem $compiler_version $liboqs_build "$input" "$SCRIPT_DIR"

# Case 5: A specific SIG
elif echo "$SIGS" | grep -Fxq "$input"; then
    # Skip SPHINCS and SLH-DSA for SIG tests
    if [[ "$input" == *SPHINCS* || "$input" == *SLH_DSA* ]]; then
        echo "Skipping $UPPER_TYPE $input" | tee -a "$SUMMARY_FILE"
        continue
    fi
    test "$BUILD_DIR" sig $compiler_version $liboqs_build "$input" "$SCRIPT_DIR"

# If none of the above, exit
else 
    echo "Enter a valid input: all/kems/sigs/<specific_variant>"
    exit 1
fi
