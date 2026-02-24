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

    echo "starting build"
    
    # Build liboqs with the current configuration
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    cmake -S .. -G Ninja -DCMAKE_C_FLAGS="$OPT_FLAG" -DCMAKE_C_COMPILER=$COMP_V -DOQS_OPT_TARGET=$LIBOQS_BUILD  -DCMAKE_BUILD_TYPE=Debug -DOQS_USE_OPENSSL=OFF -DOQS_DIST_BUILD=OFF -DOQS_ENABLE_TEST_CONSTANT_TIME=ON
    cmake --build . -j$(nproc)

    echo "finished build"

    ls -la "$BUILD_DIR"
    ls -la "$BUILD_DIR/include/oqs/oqsconfig.h"
    grep -n "CMAKE" "$BUILD_DIR/CMakeCache.txt" || true
}

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

    # Generate suppression flags for all suppression files containing false positives
    SUP_DIR="$SCRIPT_DIR/false_positives"
    SUP_FLAGS=()
    for f in "$SUP_DIR"/*.supp; do
        [ -f "$f" ] || continue
        SUP_FLAGS+=( "--suppressions=$f" )
    done

    LIBOQS_DIR="$(realpath "$SCRIPT_DIR/../../../..")"

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

    COMPILATION_FLAGS=$(grep "CMAKE_C_FLAGS:" "$BUILD_DIR/CMakeCache.txt" | cut -d'=' -f2-)

    VALGRIND_OPTS=(
        valgrind_varlat
        --tool=memcheck
        --gen-suppressions=all
        "${SUP_FLAGS[@]}"        # Include all suppression files
        --error-exitcode=123
        --max-stackframe=20480000
        --num-callers=20
        --variable-latency-errors=yes   # ENABLE the KyberSlash patch
    )

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
            echo "Compiled with: $COMPILATION_FLAGS"
            echo "Executed with: ${VALGRIND_OPTS[*]}"
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
    # Create empty files per algorithm run
    : > "$LOG_FILE"
    : > "$LOG_FILE.hashes"
    : > "$LOG_FILE.count"

    "${VALGRIND_OPTS[@]}" "$BUILD_DIR"/tests/$TEST_BINARY "$ALGORITHM" 2>&1 | awk \
        -v log_file="$LOG_FILE" \
        -v tmp_file="$LOG_FILE.tmp" \
        -v hash_file="$LOG_FILE.hashes" \
        -v count_file="$LOG_FILE.count" \
        -v max_warnings="$MAX_WARNINGS" '
    # Extract unique suppression blocks from Valgrind output
    BEGIN {
        unique_warnings_count = 0;
        in_block = 0;         # Whether we are inside a { ... } block
        block = "";           # Current block content (including braces)
        suppress = 0;         # reached max_warnings

        # Preload known hashes if present
        while ((getline line < hash_file) > 0) {
            gsub(/\r$/, "", line);  # Change Windows newlines \r\n to simple \n
            if (length(line) > 0) {
                seen[line] = 1;     # Variable storing the hashes of all the blocks already gathered
            }
        }
        close(hash_file);
    }

    {
        if (suppress) {
            # Still parse block boundaries but do nothing else (prevents SIGPIPE errors)
            if (in_block) {
                if ($0 ~ /^\}$/) { in_block = 0 }
            } else if ($0 ~ /^\{$/) {
                in_block = 1
            }
            next
        }

        if (in_block) {
            block = block $0 "\n";
                
            # When } is encountered, it is the end of block: compute hash via tmp file
            if ($0 ~ /^\}$/) {
                print block > tmp_file; close(tmp_file);   # Load the block into the tmp file
                cmd = "sha256sum \"" tmp_file "\"";        # Build a system command (cmd) that computes the hash of the block
                cmd | getline line; close(cmd);            # Execute it and read the full sha256sum output line
                hash = line; sub(/ .*/, "", hash);        # Extract the first field (hash) before the first space

                # If the hash is new, store it in seen[] and increase the count
                if (!(hash in seen)) {
                    print block >> log_file; close(log_file);
                    print "" >> log_file;      # spacer line between blocks
                    print hash >> hash_file; close(hash_file);
                    seen[hash] = 1;
                    unique_warnings_count++;

                    # If the cap is reached, exit
                    if (unique_warnings_count >= max_warnings) {
                        suppress = 1;
                    }
                }

                # Reset
                in_block = 0;
                block = "";
            }
            next
        }

        # When { is detected, start a new block
        if ($0 ~ /^\{$/) {
            in_block = 1;
            block = $0 "\n";
        }
    }

    END {
        print unique_warnings_count > count_file; close(count_file);
    }
    '
    
    # Capture the exit code of Valgrind (first element of PIPESTATUS)
    VALGRIND_EXIT_CODE=${PIPESTATUS[0]}
    AWK_EXIT_CODE=${PIPESTATUS[1]}
    EXIT_CODE=$VALGRIND_EXIT_CODE

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

    rm -f "$OUTPUT_DIR"/*.count
    rm -f "$OUTPUT_DIR"/*.hashes
    rm -f "$OUTPUT_DIR"/*log.tmp

    #echo "" | tee -a "$SUMMARY_FILE"
    #echo "$UPPER_TYPE Results: $PASS_COUNT passed, $FAIL_COUNT failed" | tee -a "$SUMMARY_FILE"
    #echo "" | tee -a "$SUMMARY_FILE"
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
echo "==== DEBUG BEFORE GET_ENABLED_ALGS ===="
echo "PWD=$(pwd)"
echo "OQS_BUILD_DIR=$OQS_BUILD_DIR"
env | grep OQS || true
echo "BUILD_DIR=$BUILD_DIR"
echo "Listing build include dir:"
ls -la "$BUILD_DIR/include" || true
echo "========================================"
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
