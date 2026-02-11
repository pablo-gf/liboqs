# Constant-Time Tooling

Automated testing framework for detecting constant-time warnings in [liboqs](https://github.com/open-quantum-safe/liboqs) cryptographic implementations using analysis tools across different compiler optimization levels, compiler versions, and liboqs builds.

## Repository Structure

```
tools/
├── memsan/
│   ├── ci_build.sh           # Script for building liboqs with different testing modes in CI
│   ├── ci_test.sh            # Script for running MemSan tests in CI
│   ├── local_build.sh        # Script for building liboqs with different testing modes locally
│   ├── local_test.sh         # Script for running MemSan tests locally
│   ├── logs/                 # Directory containing all logs for MemSan tests
│   ├── README.md             # Documentation for MemSan testing
│   ├── CMakeLists.txt        # MemSan-specific CMakeLists
│   ├── test_kem.c            # MemSan-specific kem test
│   ├── test_sig.c            # MemSan-specific sig test
│   └── rng_poison_memsan.c   # RNG poisoning for MemSan

├── valgrind_varlat/
│   ├── ci_build.sh           # Script for building liboqs with different testing modes in CI
│   ├── ci_test.sh            # Script for running MemSan tests in CI
│   ├── local_build.sh        # Script for building liboqs with different testing modes locally
│   ├── local_test.sh         # Script for running MemSan tests locally
│   ├── logs/                 # Directory containing all logs for Valgrind-Varlat tests
│   ├── README.md             # Documentation for Valgrind testing
│   ├── valgrind-try-patch-20250805.txt       # Valgrind patch file
│   ├── valgrind-varlat-patch-20250805.txt    # Valgrind variable-latency patch
│   └── valgrind-varlat-sup-block.txt         # Valgrind suppression block
├── scripts/            # helper scripts (analyze_results.py, compare_logs.py)
├── README.md
```

## Tools

### 1. Valgrind-Varlat (`valgrind_varlat/`)
- **Purpose**: Uninitialized memory error detection using patched Valgrind, which includes variable-latency errors
- **Key Scripts**:
  - `*_build.sh` - Build liboqs across compiler versions, liboqs builds, and optimization levels
  - `*_test.sh <build_dir> <kem|sig>` - Run tests on a single build
- **Output**: Unique suppression blocks for variable-latency errors (deduplicated via SHA-256 hashing)

### 2. MemSan (`memsan/`)
- **Purpose**: LLVM-based memory error detection
- **Key Scripts**:
  - `*_build.sh` - Build liboqs across compiler versions, liboqs builds, and optimization levels
  - `*_test.sh <build_dir> <kem|sig>` - Run tests on a single build
- **Output**: Unique `SUMMARY: MemorySanitizer:` lines

Each tool has two pairs of scripts: One for local testing and another for CI testing. This is because certain configurations and arrangements had to be modified so that a less resource-intensive version of the testing framework could be enabled for CI through Github Actions using `liboqs/.github\workflows\ct-tooling-valgrind-varlat.yml` and `liboqs/.github\workflows\ct-tooling-memsan.yml`. Valgrind-Varlat and MemSan tests are fully integrated into CI, categorized by compiler version, liboqs builds, and optimization flags. Valgrind-Varlat tests cover all algorithms and their variants, while MemSan tests, being more time-consuming, are limited to one variant per algorithm. These tests are executed using the default versions of clang and gcc within the container image.

### Configuration
For Valgrind-Varlat configuration, see: [Valgrind-Varlat's README](liboqs/tests/ct_tooling/tools/valgrind_varlat/README.md)
For MemSan configuration, see: [MemSan's README](liboqs/tests/ct_tooling/tools/memsan/README.md)

## Workflow

### Running Tests

Each tool follows the same testing workflow, which is implemented through two shell scripts:

1. **Building liboqs**
First, the `build.sh` script builds liboqs with the different variants that we are interested into, generating a build folder for each possible combination:

- Compiler versions: gcc, gcc-14, clang, and clang-20
- liboqs build: auto (with optimizations), and generic
- Optimization flags: -O0, -O1, -O2, -O3, -Os, -Ofast, -O2 -fno-tree-vectorize, and -O3 -fno-tree-vectorize

Note that Valgrind-Varlat tests can be compiled using both gcc and clang, while MemSan is only native to the clang compiler. This leaves the following possible configurations for each of the optimization flags:

<table>
  <thead>
    <tr>
      <th></th>
      <th colspan="4">Valgrind-Varlat</th>
      <th colspan="2">MemSan</th>
    </tr>
    <tr>
      <th></th>
      <th>gcc</th>
      <th>gcc-14</th>
      <th>clang</th>
      <th>clang-20</th>
      <th>clang</th>
      <th>clang-20</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>generic</td>
      <td>All opt flags</td>
      <td>All opt flags</td>
      <td>All opt flags</td>
      <td>All opt flags</td>
      <td>All opt flags</td>
      <td>All opt flags</td>
    </tr>
    <tr>
      <td>auto</td>
      <td>All opt flags</td>
      <td>All opt flags</td>
      <td>All opt flags</td>
      <td>All opt flags</td>
      <td>All opt flags</td>
      <td>All opt flags</td>
    </tr>
  </tbody>
</table>

Once the script builds each configuration into a build folder, it calls the test execution script (`test.sh`) on the build folder generated.

2. **Test execution**
Then, the `test.sh` script is tasked with executing the tool's test on selected liboqs algorithms. It retrieves the OQS enabled algorithms using the helpers module, and starts the constant time testing on each one of the variants that are returned. Each tool has a different process through which it parses the tool's output to keep unique instances of the warnings, which are further detailed in their respective README files: [Valgrind-Varlat's README](liboqs/tests/ct_tooling/tools/valgrind_varlat/README.md) and [MemSan's README](liboqs/tests/ct_tooling/tools/memsan/README.md).

### Output Structure
The workflow organizes test outputs into log files that capture unique warnings for each algorithm. These logs are categorized into concrete subdirectories based on the compiler and build configuration (`gcc_14_auto`, `clang_generic`, ...), which then contain further subdivisions by optimization levels (`O0`, `O1`, ...) and algorithm types (`kem` or `sig`). The structure is as follows:

```
liboqs-ct-tooling/ct-tools/<tool>/logs/
├── clang_generic/
│   ├── O0/
│   │   ├── kem/
│   │   │   ├── kem_summary_<timestamp>.txt  # Pass/fail summary
│   │   │   ├── <algorithm>_<timestamp>.log  # Unique warnings
│   │   └── sig/
│   │       └── ...
│   ├── O1/
│   └── ...
├── <compiler>_<build_config>/
│   ├── O0/
│   └── ...
```

### Simultaneous testing
Since MemSan requires to replace several files within liboqs/tests, it is not recommended to run both tests at the same time. This would cause Valgrind_Varlat tests to fail because of using MemSan-oriented files.

### Analyzing Results

Use `scripts/analyze_results.py` to parse the warnings data from the log files and generate graphs describing the results.

```bash
python3 analyze_results.py \
    --tool <Valgrind-Varlat|MemSan> \
    --input liboqs/tests/ct_testing/ct_tools/<tool>/logs \
    --output results_<tool>
```

**Generates**:
- `KEM_warnings_per_opt_level.csv` - Warning counts per algorithm per optimization
- `SIG_warnings_per_opt_level.csv` - Same for signature schemes
- `*.png` - 4 visualization graphs regarding the total and average number of warnigns per KEM and signature

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
