#!/bin/bash
# SPDX-License-Identifier: MIT

set -e

BUILD_DIR="${1:?Error: Build directory argument is required.}"
TEST_TYPE="${2:?Error: Test type argument is required (kem|sig).}"
COMP_V="${3:?Error: Compiler version is required}"
COMP_V="${COMP_V//-/_}" # Replace - with _
LIBOQS_BUILD="${4:?Error: liboqs build is required}"

# Validate TEST_TYPE
if [[ "$TEST_TYPE" != "kem" && "$TEST_TYPE" != "sig" ]]; then
    echo "Error: Test type must be 'kem' or 'sig', got '$TEST_TYPE'" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBOQS_DIR="$(realpath "$SCRIPT_DIR/../../../..")"
LOG_DIR="${SCRIPT_DIR}/logs/${COMP_V}_${LIBOQS_BUILD}"

# Ensure base log directory exists
mkdir -p "$LOG_DIR"

# Extract optimization level from BUILD_DIR
OPT_LEVEL=$(basename "$BUILD_DIR" | sed -E 's/.*-O([0-9a-zA-Z]+)(.*)/\1\2/' | sed 's/_/-/g')

CURRENT_RUN_DIR="$LOG_DIR/${OPT_LEVEL}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Create log directory
mkdir -p "$CURRENT_RUN_DIR"

# Create output directory based on test type
OUTPUT_DIR="$CURRENT_RUN_DIR/$TEST_TYPE"
mkdir -p "$OUTPUT_DIR"

cd "$LIBOQS_DIR"

# Set OQS_BUILD_DIR environment variable so helpers.py can find the correct build directory
export OQS_BUILD_DIR="$BUILD_DIR"

# Get list of algorithms based on test type
if [[ "$TEST_TYPE" == "kem" ]]; then
    ALGORITHMS=$(python3 -c "
import sys
sys.path.insert(0, 'tests')
import helpers
for kem in helpers.available_kems_by_name():
    if helpers.is_kem_enabled_by_name(kem):
        print(kem)
")
    TEST_BINARY="test_kem"
    UPPER_TYPE="KEM"
else
    ALGORITHMS=$(python3 -c "
import sys
sys.path.insert(0, 'tests')
import helpers
for sig in helpers.available_sigs_by_name():
    if helpers.is_sig_enabled_by_name(sig):
        print(sig)
")
    TEST_BINARY="test_sig"
    UPPER_TYPE="SIG"
fi

ALGO_COUNT=$(echo "$ALGORITHMS" | wc -l)

echo "Found $ALGO_COUNT ${UPPER_TYPE}s"
echo ""

COMPILATION_FLAGS=$(grep "CMAKE_C_FLAGS:" "$BUILD_DIR/CMakeCache.txt" | cut -d'=' -f2-)

VALGRIND_OPTS=(
    "valgrind_varlat"
    --tool=memcheck
    --gen-suppressions=all
    --error-exitcode=123
    --max-stackframe=20480000
    --num-callers=20
    --variable-latency-errors=yes      # ENABLE the KyberSlash patch
)

# Extract the compiler path from CMakeCache.txt in each build
COMPILER_PATH=$(grep -E '^CMAKE_C_COMPILER:.*=' "$BUILD_DIR"/CMakeCache.txt | head -n1 | cut -d'=' -f2- | tr -d '\r')
COMPILER_VERSION=$("$COMPILER_PATH" --version 2>&1 | head -n1)

# Extract system's architecture
ARCH="$(uname -m)"

MAX_WARNINGS=100000

# Run tests
echo "========================================" | tee "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
echo "Testing ${UPPER_TYPE}s" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
echo "Compiled with: $COMPILATION_FLAGS" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
echo "Executed with: ${VALGRIND_OPTS[*]}" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
echo "Compiler version: ${COMPILER_VERSION}" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
echo "Architecture: ${ARCH}" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
echo "========================================" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
echo "" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"

PASS_COUNT=0
FAIL_COUNT=0

for algo in $ALGORITHMS; do
    # Skip SPHINCS and SLH-DSA for SIG tests
    if [[ "$TEST_TYPE" == "sig" && ( "$algo" == *SPHINCS* || "$algo" == *SLH_DSA* ) ]]; then
        echo "Skipping $UPPER_TYPE $algo" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
        continue
    fi
    
    echo -n "Testing $UPPER_TYPE: $algo ... " | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
    
    LOG_FILE="$OUTPUT_DIR/${algo}_${TIMESTAMP}.log"
    # Create empty files per algorithm run
    : > "$LOG_FILE"
    : > "$LOG_FILE.hashes"
    : > "$LOG_FILE.count"

    "${VALGRIND_OPTS[@]}" "$BUILD_DIR"/tests/$TEST_BINARY "$algo" 2>&1 | awk \
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

    echo "valgrind exit code: $?"
    
    # Capture the exit code of Valgrind (first element of PIPESTATUS)
    VALGRIND_EXIT_CODE=${PIPESTATUS[0]}
    AWK_EXIT_CODE=${PIPESTATUS[1]}
    EXIT_CODE=$VALGRIND_EXIT_CODE

    ERROR_COUNT=$(cat "$LOG_FILE.count" 2>/dev/null)
    ERROR_COUNT=${ERROR_COUNT:-0}

    if [ "$ERROR_COUNT" -eq "$MAX_WARNINGS" ]; then
        echo "FAIL (Valgrind Kyberslash warnings)" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
        echo "  → Found $ERROR_COUNT Valgrind Kyberslash warnings (warning cap reached — further warnings suppressed)" \
            | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
        ((++FAIL_COUNT))

    elif [ "$ERROR_COUNT" -gt 0 ]; then
        echo "FAIL (Valgrind Kyberslash warnings)" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
        echo "  → Found $ERROR_COUNT Valgrind Kyberslash warnings" \
            | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
        ((++FAIL_COUNT))

    elif [ $EXIT_CODE -ne 0 ]; then
        echo "FAIL (Exit code: $EXIT_CODE)" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
        ((++FAIL_COUNT))

    else
        echo "PASS" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
        ((++PASS_COUNT))

    fi
done

rm -f "$OUTPUT_DIR"/*.count
rm -f "$OUTPUT_DIR"/*.hashes
rm -f "$OUTPUT_DIR"/*log.tmp

echo "" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
echo "$UPPER_TYPE Results: $PASS_COUNT passed, $FAIL_COUNT failed" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
echo "" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"