#!/bin/bash
# SPDX-License-Identifier: MIT

set -e

BUILD_DIR="${1:?Error: Build directory argument is required.}"
COMP_V="${2:?Error: Compiler version is required}"
COMP_V="${COMP_V//-/_}" # Replace - with _
LIBOQS_BUILD="${3:?Error: liboqs build is required}"
ALGORITHM="${4:?Error: Algorithm is required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBOQS_DIR="$(realpath "$SCRIPT_DIR/../../../..")"
OUTPUT_DIR="${SCRIPT_DIR}/logs"

# Ensure base log directory exists
mkdir -p "$OUTPUT_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

cd "$LIBOQS_DIR"

# Retrieve MemSan compilation options from CMakeCache.txt
MEMSAN_OPTIONS=$(grep "CMAKE_C_FLAGS:" "$BUILD_DIR/CMakeCache.txt" | cut -d'=' -f2-)

# Extract the compiler path from CMakeCache.txt in each build
COMPILER_PATH=$(grep -E '^CMAKE_C_COMPILER:.*=' "$BUILD_DIR"/CMakeCache.txt | head -n1 | cut -d'=' -f2- | tr -d '\r')
COMPILER_VERSION=$("$COMPILER_PATH" --version 2>&1 | head -n1)

# Extract system's architecture
ARCH="$(uname -m)"

# Select test binary
if [[ "$ALGORITHM" == "BIKE-L1" || "$ALGORITHM" == "Classic-McEliece-348864" || "$ALGORITHM" == "Kyber512" || "$ALGORITHM" == "ML-KEM-512" || "$ALGORITHM" == "sntrup761" || "$ALGORITHM" == "FrodoKEM-640-AES" ]]; then
    TEST_BINARY="test_kem"
else
    TEST_BINARY="test_sig"

# Run tests
echo "========================================" | tee "$OUTPUT_DIR/${ALGORITHM}_summary_${TIMESTAMP}.txt"
echo "Testing ${ALGORITHM}" | tee -a "$OUTPUT_DIR/${ALGORITHM}_summary_${TIMESTAMP}.txt"
echo "Compiled with: $MEMSAN_OPTIONS" | tee -a "$OUTPUT_DIR/${ALGORITHM}_summary_${TIMESTAMP}.txt"
echo "Compiler version: ${COMPILER_VERSION}" | tee -a "$OUTPUT_DIR/${ALGORITHM}_summary_${TIMESTAMP}.txt"
echo "Architecture: ${ARCH}" | tee -a "$OUTPUT_DIR/${ALGORITHM}_summary_${TIMESTAMP}.txt"
echo "========================================" | tee -a "$OUTPUT_DIR/${ALGORITHM}_summary_${TIMESTAMP}.txt"
echo "" | tee -a "$OUTPUT_DIR/${ALGORITHM}_summary_${TIMESTAMP}.txt"

MAX_WARNINGS=100000

PASS_COUNT=0
FAIL_COUNT=0
   
echo -n "Testing $ALGORITHM ... " | tee -a "$OUTPUT_DIR/${ALGORITHM}_summary_${TIMESTAMP}.txt"

LOG_FILE="$OUTPUT_DIR/${ALGORITHM}_${TIMESTAMP}.log"
touch "$LOG_FILE"

# Only count and store unique summary lines
# Exit early if warning count exceeds MAX_WARNINGS threshold
"$BUILD_DIR"/tests/$TEST_BINARY "$ALGORITHM" 2>&1 | awk -v log_file="$LOG_FILE" -v max_warnings="$MAX_WARNINGS" '
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
    echo "FAIL (MemSan warnings)" | tee -a "$OUTPUT_DIR/${ALGORITHM}_summary_${TIMESTAMP}.txt"
    echo "  → Found $ERROR_COUNT MemSan warnings (warning cap reached — further warnings suppressed)" | tee -a "$OUTPUT_DIR/${ALGORITHM}_summary_${TIMESTAMP}.txt"
    ((++FAIL_COUNT))
elif [ "$ERROR_COUNT" -gt 0 ]; then
    echo "FAIL (MemSan warnings)" | tee -a "$OUTPUT_DIR/${ALGORITHM}_summary_${TIMESTAMP}.txt"
    echo "  → Found $ERROR_COUNT MemSan warnings" | tee -a "$OUTPUT_DIR/${ALGORITHM}_summary_${TIMESTAMP}.txt"
    ((++FAIL_COUNT))
elif [ $EXIT_CODE -ne 0 ]; then
    echo "FAIL (Exit code: $EXIT_CODE)" | tee -a "$OUTPUT_DIR/${ALGORITHM}_summary_${TIMESTAMP}.txt"
    ((++FAIL_COUNT))
else
    echo "PASS" | tee -a "$OUTPUT_DIR/${ALGORITHM}_summary_${TIMESTAMP}.txt"
    ((++PASS_COUNT))
fi


rm -f "$OUTPUT_DIR"/*.log.count

echo "" | tee -a "$OUTPUT_DIR/${ALGORITHM}_summary_${TIMESTAMP}.txt"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed" | tee -a "$OUTPUT_DIR/${ALGORITHM}_summary_${TIMESTAMP}.txt"
echo "" | tee -a "$OUTPUT_DIR/${ALGORITHM}_summary_${TIMESTAMP}.txt"