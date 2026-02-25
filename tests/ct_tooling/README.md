# Constant-Time Tooling

Framework for running constant-time (CT) tests in liboqs across compilers, optimization flags, and `OQS_OPT_TARGET` build modes.

## Repository Structure

```
tests/ct_tooling/
├── README.md
├── scripts/
│   ├── analyze_results.py         # Script that handles logs data           
│   └── compare_logs.py            # Script that compares two log files have the same or distinct warnings
└── tools/
    ├── memsan/
    │   ├── CMakeLists.txt          # Documentation for MemSan testing
    │   ├── ct_test.sh              # Shell script handling CT test execution
    │   ├── local_build_options.sh  # Shell script for testing compiler options locally  
    │   ├── rng_poison_memsan.c     # RNG poisoning for MemSan testing
    │   ├── test_kem.c              # MemSan-specific sig test
    │   ├── test_sig.c              # MemSan-specific sig test
    │   └── README.md
    └── valgrind_varlat/
        ├── ct_test.sh              # Shell script handling CT test execution                                                                                                  
        ├── local_build_options.sh  # Shell script for testing compiler options locally                                                                                                
        ├── false_positives/        # Directory containing false-posiotives suppression files
        │   └── *.supp
        ├── valgrind-try-patch-20250805.txt     # Valgrind patch file
        ├── valgrind-varlat-patch-20250805.txt  # Valgrind variable-latency patch
        ├── valgrind-varlat-sup-block.txt       # Valgrind suppression block
        └── README.md
```

## Tools

### 1. Valgrind-Varlat (`valgrind_varlat/`)
- **Purpose**: Uninitialized memory error detection for cosntant-time analysis using Kyberslash patch for Valgrind
- **Output**: Directory containing allUnique suppression blocks for each warning output

### 2. MemSan (`memsan/`)
- **Purpose**: LLVM-based uninitialized memory error detection for constant-time analysis using MemorySanitizer
- **Output**: Unique `SUMMARY: MemorySanitizer` lines for each warning output

Both tools use their respective `ct_testing.sh` script with the same argument structure for testing:

```bash
./ct_test.sh <compiler_version> <liboqs_build> <opt_flags...> <input>
```

- `compiler_version`: clang, clang-20, gcc, gcc14 , ...
- `liboqs_build`: `generic` or `auto`
- `input`: all, kems, sigs, or a specific enabled algorithm variant
- `opt_flags`: All arguments from position 3 up to position N-1 are treated as compiler optimization flags (including multi-flag combinations such as `-O3 -fno-tree-vectorize`).

Examples:

```bash
./ct_test.sh clang generic -O2 all
./ct_test.sh clang-20 auto -O3 -fno-tree-vectorize kems
./ct_test.sh gcc-14 generic -O2 -fno-tree-vectorize Kyber768
./ct_test.sh clang generic -O1 Dilithium2
```

The `local_build_options.sh` shell script uses `ct_test.sh` to execute CT test locally on all liboqs algorithms across a variety of compilers, compiler versions, liboqs target builds, and optimization flags.

The `ct-tooling-valgrind-varlat.yml` and `ct-tooling-memsan.yml` workflows also use `ct_testing.sh` to execute CT tests in CI on user-selected algorithms (using [interactive-inputs](https://github.com/marketplace/actions/interactive-inputs)) when the workflows are manually triggered on GitHub Actions.

### Configuration
For Valgrind-Varlat configuration, see: [Valgrind-Varlat's README](liboqs/tests/ct_tooling/tools/valgrind_varlat/README.md)
For MemSan configuration, see: [MemSan's README](liboqs/tests/ct_tooling/tools/memsan/README.md)

## Workflow

### Running Tests

Each tool follows the same testing workflow, which is implemented through two functions within the `ct_test.sh` script:

1. **Building liboqs**
First, the `build()` function builds liboqs with the compiler options desired. In the case of `local_build_options.sh`, these options are:

- Compiler versions: gcc, gcc-14, clang, and clang-20
- liboqs build: auto (with optimizations), and generic
- Optimization flags: -O0, -O1, -O2, -O3, -Os, -Ofast, -O2 -fno-tree-vectorize, and -O3 -fno-tree-vectorize

When `ct_test.sh` is executed on a single algorithm variant, `build()` builds liboqs with the `OQS_MINIMAL_BUILD` option, minimizing the time and resources required for building. For the other input options, liboqs is built entirely.

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

Once the script builds each configuration into a build folder, it calls the test execution function (`test()`) on the build folder generated.

2. **Test execution**
Then, `test()` is tasked with executing the tool's test on selected liboqs algorithms. Each tool has a different process through which it parses the tool's output to keep unique instances of the warnings, which are further detailed in their respective README files: [Valgrind-Varlat's README](liboqs/tests/ct_tooling/tools/valgrind_varlat/README.md) and [MemSan's README](liboqs/tests/ct_tooling/tools/memsan/README.md).

### Output Structure
The workflow organizes test outputs into log files that capture unique warnings for each algorithm. These logs are categorized into concrete subdirectories based on the compiler and build configuration (`gcc_14_auto`, `clang_generic`, ...), which then contain further subdivisions by optimization levels (`O0`, `O1`, ...) and algorithm types (`kem` or `sig`). The structure is as follows:

```
liboqs-ct-tooling/ct-tools/<tool>/logs/
├── clang_generic/
│   ├── O0/
│   │   ├── kem/
│   │   │   ├── kem_summary.txt  # Pass/fail summary
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