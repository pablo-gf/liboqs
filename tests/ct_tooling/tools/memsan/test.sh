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
OPT_LEVEL=$(basename "$BUILD_DIR" | sed 's/build_//')

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

# Retrieve MemSan compilation options from CMakeCache.txt
MEMSAN_OPTIONS=$(grep "CMAKE_C_FLAGS:" "$BUILD_DIR/CMakeCache.txt" | cut -d'=' -f2-)

# Extract the compiler path from CMakeCache.txt in each build
COMPILER_PATH=$(grep -E '^CMAKE_C_COMPILER:.*=' "$BUILD_DIR"/CMakeCache.txt | head -n1 | cut -d'=' -f2- | tr -d '\r')
COMPILER_VERSION=$("$COMPILER_PATH" --version 2>&1 | head -n1)

# Extract system's architecture
ARCH="$(uname -m)"

MAX_WARNINGS=100000

# Run tests
echo "========================================" | tee "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
echo "Testing ${UPPER_TYPE}s" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
echo "Compiled with: $MEMSAN_OPTIONS" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
echo "Compiler version: ${COMPILER_VERSION}" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
echo "Architecture: ${ARCH}" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
echo "========================================" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
echo "" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"

PASS_COUNT=0
FAIL_COUNT=0

for algo in $ALGORITHMS; do
    # Skip SPHINCS, SLH-DSA, and only one variant for ML-DSA and OV for SIG tests
    if [[ "$TEST_TYPE" == "sig" ]]; then
        if [[ "$algo" == "ML-DSA"* && "$algo" != "ML-DSA-44" ]]; then
            echo "Skipping $UPPER_TYPE: $algo" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
            continue
        elif [[ "$algo" == "OV-Is-pkc"* && "$algo" != "OV-Is-pkc-skc" ]]; then
            echo "Skipping $UPPER_TYPE: $algo" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
            continue
        elif [[ "$algo" == *SPHINCS* || "$algo" == *SLH_DSA* ]]; then
            echo "Skipping $UPPER_TYPE: $algo" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
            continue
        fi
    fi
    
    echo -n "Testing $UPPER_TYPE: $algo ... " | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"

    LOG_FILE="$OUTPUT_DIR/${algo}_${TIMESTAMP}.log"
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
        echo "FAIL (MemSan warnings)" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
        echo "  → Found $ERROR_COUNT MemSan warnings (warning cap reached — further warnings suppressed)" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
        ((++FAIL_COUNT))
    elif [ "$ERROR_COUNT" -gt 0 ]; then
        echo "FAIL (MemSan warnings)" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
        echo "  → Found $ERROR_COUNT MemSan warnings" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
        ((++FAIL_COUNT))
    elif [ $EXIT_CODE -ne 0 ]; then
        echo "FAIL (Exit code: $EXIT_CODE)" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
        ((++FAIL_COUNT))
    else
        echo "PASS" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
        ((++PASS_COUNT))
    fi
done

rm -f "$OUTPUT_DIR"/*.log.count

echo "" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
echo "$UPPER_TYPE Results: $PASS_COUNT passed, $FAIL_COUNT failed" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"
echo "" | tee -a "$OUTPUT_DIR/${TEST_TYPE}_summary_${TIMESTAMP}.txt"