# Constant-Time Tooling

Framework for constant-time testing of liboqs across compilers, optimization flags, and `OQS_OPT_TARGET` build modes.

## Repository Structure

```
tests/ct_tooling/
├── README.md
├── ct_test.sh                  # Unified shell script handling CT test execution for all tools
├── local_testing_example.sh    # Example script for running CT tests locally
├── analyze_results.py          # Parse log output and generate summary CSVs and graphs
└── tools/
    ├── memsan/
    │   ├── CMakeLists.txt          # MemSan-specific CMake configuration for liboqs/tests
    │   ├── rng_poison_memsan.c     # RNG poisoning for MemSan testing
    │   ├── test_kem.c              # MemSan-specific KEM test
    │   ├── test_sig.c              # MemSan-specific SIG test
    │   └── README.md
    └── valgrind_varlat/
        ├── false_positives/        # Directory containing false-positives suppression files
        │   └── *.supp
        ├── valgrind-try-patch-20250805.txt     # Valgrind patch file
        ├── valgrind-varlat-patch-20250805.txt  # Valgrind variable-latency patch
        ├── valgrind-varlat-sup-block.txt       # Valgrind suppression block
        └── README.md
```

## Tools

### 1. Valgrind-Varlat (`valgrind_varlat/`)
- **Purpose**: Uninitialized memory error detection for constant-time analysis using Kyberslash patch for Valgrind
- **Output**: Directory containing all unique suppression blocks for each warning output

### 2. MemSan (`memsan/`)
- **Purpose**: LLVM-based uninitialized memory error detection for constant-time analysis using MemorySanitizer
- **Output**: Unique `SUMMARY: MemorySanitizer` lines for each warning output

Both tools are driven by the single unified `ct_test.sh` script located at the root of `tests/ct_tooling/`. The tool to execute is selected via the first argument:

```bash
./ct_test.sh <tool> <compiler_version> <liboqs_build> <opt_flags...> <input>
```

- `tool`: `valgrind-varlat` or `memsan`
- `compiler_version`: clang, clang-20, gcc, gcc-14, ...
- `liboqs_build`: `generic` or `auto`
- `input`: `all`, `kems`, `sigs`, or a specific enabled algorithm variant
- `opt_flags`: All arguments from position 4 up to position N-1 are treated as compiler optimization flags (including multi-flag combinations such as `-O3 -fno-tree-vectorize`).

Examples:

```bash
./ct_test.sh valgrind-varlat clang generic -O2 all
./ct_test.sh valgrind-varlat clang-20 auto -O3 -fno-tree-vectorize kems
./ct_test.sh valgrind-varlat gcc-14 generic -O2 -fno-tree-vectorize Kyber768
./ct_test.sh memsan clang generic -O1 ML-DSA-44
./ct_test.sh memsan clang-20 auto -O3 all
```

The `local_testing_example.sh` script demonstrates how to use `ct_test.sh` to run CT tests locally across a variety of compilers, compiler versions, liboqs target builds, and optimization flags.

The `ct-tooling-valgrind-varlat.yml` and `ct-tooling-memsan.yml` workflows also use `ct_test.sh` to execute CT tests in CI on user-selected algorithms (using [interactive-inputs](https://github.com/marketplace/actions/interactive-inputs)) when the workflows are manually triggered on GitHub Actions.

### Configuration
For Valgrind-Varlat configuration, see: [Valgrind-Varlat's README](tools/valgrind_varlat/README.md)
For MemSan configuration, see: [MemSan's README](tools/memsan/README.md)

## Workflow

### Running Tests

Each tool follows the same testing workflow, implemented through two functions in the unified `ct_test.sh` script:

1. **Building liboqs**
First, the `build()` function builds liboqs with the compiler options desired. In the case of `local_testing_example.sh`, these options are set to:

- Compiler versions: gcc, gcc-14, clang, and clang-20
- liboqs build: auto (with optimizations), and generic
- Optimization flags: -O0, -O1, -O2, -O3, -Os, -Ofast, -O2 -fno-tree-vectorize, and -O3 -fno-tree-vectorize

When `ct_test.sh` is executed on a single algorithm variant, `build()` builds liboqs with the `OQS_MINIMAL_BUILD` option, minimizing the time and resources required for building. For the other input options, liboqs is built entirely. Each build is placed into a dedicated directory at the liboqs root, named using the pattern.

Note that Valgrind-Varlat tests can be compiled using both gcc and clang, while MemSan is only native to the clang compiler. This leaves the following possible configurations for each of the optimization flags in the case of `local_testing_example.sh`:

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
Then, `test()` is tasked with executing the tool's test on selected liboqs algorithms. Each tool has a different process through which it parses the tool's output to keep unique instances of the warnings, which are further detailed in their respective README files: [Valgrind-Varlat's README](tools/valgrind_varlat/README.md) and [MemSan's README](tools/memsan/README.md).

Both tools enforce a warning cap of 100,000 unique warnings per algorithm run. Once the cap is reached, further warnings are suppressed. All SPHINCS and SLH-DSA signature variants are currently skipped during SIG tests due to the excessive time they require to execute.

### Output Structure
The workflow organizes test outputs into log files that capture unique warnings for each algorithm. These logs are written inside `tests/ct_tooling/tools/<tool>/logs/`, categorized into concrete subdirectories based on the compiler and build configuration (`gcc_14_auto`, `clang_generic`, ...), which then contain further subdivisions by optimization levels (`O0`, `O1`, ...) and algorithm types (`kem` or `sig`). The structure is as follows:

```
tests/ct_tooling/tools/<tool>/logs/
├── clang_generic/
│   ├── O0/
│   │   ├── kem/
│   │   │   ├── kem_summary.txt              # Pass/fail summary with compiler info
│   │   │   ├── <algorithm>_<timestamp>.log  # Unique warnings for the algorithm
│   │   └── sig/
│   │       └── ...
│   ├── O1/
│   └── ...
├── <compiler>_<build_config>/
│   ├── O0/
│   └── ...
```

The summary file for each run includes the compiler path, compiler version, target architecture, and compilation flags used, followed by a pass/fail line for each algorithm tested.

### Suppression files for false positive handling

- Valgrind-Varlat:

Here is an example of a suppression file:

```text
    {
    Rejection sampling to produce public "A" matrix
    Memcheck:Cond
    fun:rej_uniform
    fun:PQCLEAN_KYBER*_CLEAN_gen_matrix
    }
```

The brackets wrap a single error that is to be suppressed. Within the brackets, the first line is a comment. The remaining lines tell Valgrind to ignore any "Memcheck:Cond" errors that occur when a function named rej_uniform is called from a function whose name matches the glob pattern PQCLEAN_KYBER*_CLEAN_gen_matrix.

Before this suppression file was written, a run of this script produced the following output.
```text
    ==594== Conditional jump or move depends on uninitialised value(s)
    ==594==    at 0x22550D: rej_uniform (indcpa.c:133)
    ==594==    by 0x225654: PQCLEAN_KYBER512_CLEAN_gen_matrix (indcpa.c:177)
    ==594==    by 0x2257D1: PQCLEAN_KYBER512_CLEAN_indcpa_keypair (indcpa.c:216)
    ==594==    by 0x1B6C1E: PQCLEAN_KYBER512_CLEAN_crypto_kem_keypair (kem.c:26)
    ==594==    by 0x1B6B9F: OQS_KEM_kyber_512_keypair (kem_kyber_512.c:56)
    ==594==    by 0x10D123: OQS_KEM_keypair (kem.c:818)
    ==594==    by 0x10AD07: kem_test_correctness (test_kem.c:103)
    ==594==    by 0x10B4E7: test_wrapper (test_kem.c:186)
    ==594==    by 0x4CDAFA2: start_thread (pthread_create.c:486)
    ==594==    by 0x4DED4CE: clone (clone.S:95)
    ==594==
    {
       <insert_a_suppression_name_here>
       Memcheck:Cond
       fun:rej_uniform
       fun:PQCLEAN_KYBER512_CLEAN_gen_matrix
       fun:PQCLEAN_KYBER512_CLEAN_indcpa_keypair
       fun:PQCLEAN_KYBER512_CLEAN_crypto_kem_keypair
       fun:OQS_KEM_kyber_512_keypair
       fun:OQS_KEM_keypair
       fun:kem_test_correctness
       fun:test_wrapper
       fun:start_thread
       fun:clone
    }
```
The lines beginning with "==" are a Valgrind error message. The bracketed text is a suppression file template. To produce the final suppression file we added a comment, replaced "512" with a  wildcard (since an identical error occurs in other Kyber parameter sets), and truncated the backtrace (since the extra lines provide no interesting information to auditors).

The "fun:rej_uniform" line says to ignore _all_ Memcheck:Cond errors in rej_uniform, but Valgrind told us that line 133 was the problem. Any "fun:name" line in the backtrace can be replaced by an equivalent "src:file:line", so we could have narrowed the scope of our suppression:
```text
    {
       Rejection sampling to produce public "A" matrix
       Memcheck:Cond
       src:indcpa.c:133 # fun:rej_uniform
       fun:PQCLEAN_KYBER*_CLEAN_gen_matrix
    }
```
Here "# fun:rej_uniform" is a comment. An update to the Kyber source code might break our suppression file by changing the line number, and leaving the function name as a comment might help a future reviewer.

An ellipsis (...) can serve as a wildcard for a portion of the backtrace. We could have written:
```text
    {
       Rejection sampling to produce public "A" matrix
       Memcheck:Cond
       ...
       fun:PQCLEAN_KYBER*_CLEAN_gen_matrix
    }
```
But this is perhaps too concise. Remember that the goal here is to help auditors.

Further information can be found in Valgrind's manual. See
    https://www.valgrind.org/docs/manual/manual-core.html#manual-core.suppress
and
    https://www.valgrind.org/docs/manual/mc-manual.html#mc-manual.suppfiles

- MemSan:

MemSan follows a similar suppression mechanism to that of Valgrind-Varlat.Users can specify entities to ignore during testing by listing them in a suppression file, using a prefix that defines the entity's type. For this framework, the `fun:` prefix is used (although there are others too), since the observed false-positivesoriginate from specific functions. The suppression file is then passed to clang at compile-time using the `-fsanitize-ignorelist` flag.

MemSan's output also includes a full stack trace leading to the root cause. To successfully suppress a warning, the suppression file must target the exact function listed in the report's SUMMARY line. For example, given an output of the form:

```text
==9793==WARNING: MemorySanitizer: use-of-uninitialized-value
    #0 0x7eb79d2bf3f2 in sampling.c:62:9
    #1 0x7eb79d2bf3f2 in sampling.c:138:10
    #2 0x7eb79d2bf3f2 in sampling.c:174:12
    #3 0x7eb79d2bd57d in indcpa.c:278:5
    #4 0x7eb79d2bd57d in indcpa.c:508:3
    #5 0x7eb79d2be04a in kem.c:416:9
    #6 0x5d25bce8bce2 in test_kem.c:63:7
    #7 0x5d25bce8bce2 in test_kem.c:293:15
    #8 0x5d25bce8b4a5 in test_kem.c:391:12
    #9 0x7eb79ce9caa3 in pthread_create.c:447:8
    #10 0x7eb79cf29c6b in clone3.S:78

SUMMARY: MemorySanitizer: use-of-uninitialized-value /home/pablogf/liboqs/src/kem/ml_kem/mlkem-native_ml-kem-512_ref/mlkem/src/sampling.c:62:9 in mlk_rej_uniform_c
==9793==WARNING: MemorySanitizer: use-of-uninitialized-value
```

The framework will disregard this warning on future executions by including the following line in the suppression file:
```text
fun:mlk_rej_uniform_c
```
MemSan also enables the use of the wildcard (*) within the suppression files.

Each family of algorithms will have a specific suppression block listing the functions that output false-positives. The framework includes all suppression files by default during testing.

For further information see https://clang.llvm.org/docs/MemorySanitizer.html and https://clang.llvm.org/docs/SanitizerSpecialCaseList.html

### Simultaneous testing
Since MemSan requires to replace several files within liboqs/tests, it is not recommended to run both tests at the same time. This would cause Valgrind_Varlat tests to fail because of using MemSan-oriented files.

### Analyzing Results

Use `analyze_results.py` to parse the warnings data from the log files and generate graphs describing the results.

```bash
python3 analyze_results.py \
    --tool <Valgrind-Varlat|MemSan> \
    --input tests/ct_tooling/tools/<tool>/logs \
    --output results_<tool>
```

**Generates**:
- `KEM_warnings_per_opt_level.csv` - Warning counts per algorithm per optimization
- `SIG_warnings_per_opt_level.csv` - Same for signature schemes
- `*.png` - 4 visualization graphs regarding the total and average number of warnings per KEM and signature