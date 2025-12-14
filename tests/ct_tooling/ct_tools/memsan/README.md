# MEMSAN

This directory contains the files required to execute MemSan's tooling for liboqs constant-time testing.

## Compiling liboqs with MemSan
MemSan is inherently included with the clang compiler, so no requirement besides installing clang is needed. However, it does require certain workarounds to mark memory as uninitialized and execute constant-time testing on liboqs. Nonetheless, this process is directly carried within the `opt_flags.sh` script.

The `rng_poison_msan.c` file is used to overwrite the original `OQS_randombytes()` and mark secret variables as uninitialized. Note that the actual value is filled with a non-zero buffer (0xA5) to prevent masking of bugs, as well as eliminating any random noise in the heap memory.

For MemSan liboqs testing, it is necessary to compile liboqs with new versions of `tests/CMakeLists.txt`, `tests/test_kem.c`, `tests_sig.c`, which can be found under the repository ct-tools/memsan. These new versions allow for memory "poisoning" during the "randombytes" function in `CMakeLists.txt`, and memory "unpoisioning" of public keys in `test_kem.c` and `test_sig.c`.

Therefore, the `opt_flags.sh` script replaces the original files with the "poisoned" ones during compilation, so that MemSan testing can successfully take place. Once liboqs compilation is ready, the script replaces the original files with a backup that was temporarily stored so that liboqs is unchanged after constant-time testing with MemSan is finished.

## Algorithms Testing
Because of how many warnings are output, it is not feasible to store all the warnings in terms of memory and runtime. Therefore, the `on_liboqs.sh` script handles MemSan's output as follows:
- Since the SUMMARY line contains the overall information of the issue with the file and line, that is the data that will be logged into the log file for the sake of simplicity.
- These unique summary lines will be the ones counted as warnings, since the same warning may be output several times throughout the execution.

The testing framework currently disregarding all SPHINCS, ML-DSA tests due to the execessive length of time they require to execute. ML-DSA and UOV are only currently tested for one single variant for the same reason.