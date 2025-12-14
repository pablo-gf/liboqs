# liboqs Constant-Time Tooling

Automated testing framework for detecting constant-time warnings in [liboqs](https://github.com/open-quantum-safe/liboqs) cryptographic implementations using analysis tools across different compiler optimization levels, compiler versions, and liboqs builds.

## Repository Structure

```
ct_tools/
├── memsan/
│   ├── opt_flags.sh          # Script for building liboqs with different testing modes
│   ├── on_liboqs.sh          # Script for running MemSan tests
│   ├── logs/                 # Directory containing all logs for MemSan tests
│   ├── README.md             # Documentation for MemSan testing
│   ├── CMakeLists.txt        # MemSan-specific CMakeLists
│   ├── test_kem.c            # MemSan-specific kem test
│   ├── test_sig.c            # MemSan-specific sig test
│   └── rng_poison_memsan.c   # RNG poisoning for MemSan

├── valgrind_varlat/
│   ├── opt_flags.sh          # Script for building liboqs with different testing modes
│   ├── on_liboqs.sh          # Script for running MemSan tests
│   ├── logs/                 # Directory containing all logs for valgrind_varlat tests
│   ├── README.md             # Documentation for Valgrind testing
│   ├── valgrind-try-patch-20250805.txt       # Valgrind patch file
│   ├── valgrind-varlat-patch-20250805.txt    # Valgrind variable-latency patch
│   └──valgrind-varlat-sup-block.txt         # Valgrind suppression block
├── results/            # Aggregated results (CSVs and figures) per experiment
├── scripts/            # helper scripts (analyze_results.py, compare_logs.py)
├── README.md
```

## Tools

### 1. Valgrind (`valgrind/`)
- **Purpose**: Detect uninitialized memory reads (constant-time violations)
- **Key Scripts**:
  - `valgrind_on_liboqs.sh <build_dir> <kem|sig>` - Run tests on a single build
  - `valgrind_compiler_opts.sh` - Test across all optimization levels
- **Output**: Unique suppression blocks (deduplicated via SHA-256 hashing)

### 2. MemorySanitizer (`memsan/`)
- **Purpose**: LLVM-based memory error detection
- **Key Scripts**:
  - `opt_flags.sh` - Builds liboqs with MemSan and runs tests
- **Output**: Unique `SUMMARY: MemorySanitizer:` lines

### 3. KyberSlash (`kyberslash/`)
- **Purpose**: Variable-latency error detection using patched Valgrind
- **Key Scripts**:
  - `kyberslash_on_liboqs.sh <build_dir> <kem|sig>` - Run tests on a single build
  - `kyberslash_compiler_opts.sh` - Test across all optimization levels
- **Output**: Unique suppression blocks for variable-latency errors (deduplicated via SHA-256 hashing)

## Workflow

### Running Tests

Each tool follows the same pattern:

1. **Single optimization level**:
   ```bash
   cd <tool>/liboqs-ci-repl
   ./<tool>_on_liboqs.sh /path/to/build_O0 kem
   ./<tool>_on_liboqs.sh /path/to/build_O0 sig
   ```

2. **All optimization levels** (`O0`, `O1`, `O2`, `O3`, `Os`, `Ofast`, `O2-fno-tree-vectorize`, `O3-fno-tree-vectorize`):
   ```bash
   cd <tool>/liboqs-ci-repl
   ./<tool>_compiler_opts.sh
   ```

### Output Structure

```
<tool>/liboqs-ci-repl/<tool>_logs/
├── O0/
│   ├── kem/
│   │   ├── kem_summary_<timestamp>.txt  # Pass/fail summary
│   │   ├── <algorithm>_<timestamp>.log  # Unique warnings
│   └── sig/
│       └── ...
├── O1/
└── ...
```

### Analyzing Results

```bash
python3 analyze_results.py \
    --tool <valgrind|memsan|kyberslash> \
    --input <tool>/liboqs-ci-repl/<tool>_logs \
    --output results_<tool>
```

**Generates**:
- `KEM_warnings_per_opt_level.csv` - Warning counts per algorithm per optimization
- `SIG_warnings_per_opt_level.csv` - Same for signature schemes
- `*.png` - Visualization graphs

### Comparing logs between tools

Use `scripts/compare_blocks.py` to compare `{ ... }` suppression blocks between two log files. The script prints a short report to stdout and can write canonical block outputs to a directory when `--out-dir` is provided.

Example:

```bash
python3 scripts/compare_blocks.py --tool-a valgrind --tool-b kyberslash \
  /path/to/valgrind_algo.log /path/to/kyberslash_algo.log --out-dir log_comparison/val_vs_ks_algo
```

If `--out-dir` is specified the script writes three files into that directory:

- `only_in_<tool_a>.txt` — blocks only present in file A
- `only_in_<tool_b>.txt` — blocks only present in file B
- `in_both.txt` — blocks present in both files

Each output file contains one canonical block per unique warning and is useful for manual inspection or downstream aggregation.

## Key Features

### Deduplication
- **Valgrind/KyberSlash**: SHA-256 hashing of suppression blocks `{...}`
- **MemSan**: Exact string matching of `SUMMARY:` lines

### Algorithm Filtering
- **Skipped**: `SPHINCS*`, `SLH_DSA*` for signature tests (too slow/noisy)
- **Automatic discovery**: Uses liboqs `helpers.py` to enumerate enabled algorithms

### Warning Cap
- Maximum 100,000 unique warnings per algorithm to prevent resource exhaustion

## Configuration

### Compiler Flags
Each `<tool>_compiler_opts.sh` configures:
- **Valgrind/KyberSlash**: GCC with `-fno-tree-vectorize` variants
- **MemSan**: Clang with `-fsanitize=memory -fsanitize-recover=all`

## Dependencies

- **Valgrind**: Standard memcheck tool
- **KyberSlash**: Patched Valgrind from `~/valgrind-kyberslash/bin/valgrind`
- **MemSan**: Clang compiler with sanitizer support
- **Python**: `matplotlib`, `numpy` for result analysis

## Example

```bash
# Build and test with Valgrind across all optimizations
cd valgrind/liboqs-ci-repl
./valgrind_compiler_opts.sh

# Analyze results
python3 ../../analyze_results.py -t valgrind -i valgrind_logs -o ../../results_valgrind

# View summary
cat ../../results_valgrind/KEM_warnings_per_opt_level.csv
```