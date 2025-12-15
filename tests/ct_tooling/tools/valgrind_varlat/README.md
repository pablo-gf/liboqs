# VALGRINDVARLAT

This directory contains the necessary files to execute Valgrind's memcheck tool on liboqs with [Bernstein's Kyberslash patches](https://kyberslash.cr.yp.to/papers.html) (valgrind-try-patch-20250805.txt and valgrind-varlat-patch-20250805.txt) and another patch including variable latency warnings in the suppression block (valgrind_varlat_sup_block.txt).

## ValgrindVarlat Install Requirements
In order to successfully execute ValgrindVarlat's test using the tooling developed in this subrepository follow the next steps:

- Install valgrind using the official git repository.

```
VALGRIND_REPO="https://sourceware.org/git/valgrind.git"
TRY_PATCH="valgrind-try-patch-20250805.txt"
VARLAT_PATCH="valgrind-varlat-patch-20250805.txt"
SUP_BLOCK_PATCH="valgrind-varlat-sup-block.txt"
INSTALL_DIR="$HOME/valgrind_varlat"

# Clone the Valgrind repository
git clone "$VALGRIND_REPO" valgrind_varlat
cd valgrind_varlat
```

- Apply Bernstein's patches.

```
git apply --check "../valgrind-try-patch-20250805.txt"
git apply --check "../valgrind-varlat-patch-20250805.txt"
```

- Apply the suppression block patch.

```
git apply --check "../valgrind-varlat-sup-block.txt"
```

- Include the resultant version of valgrind into PATH under .

```
# Build and install valgrind_varlat
./autogen.sh
./configure --prefix="$INSTALL_DIR"
make -j$(nproc)
make install

# Rename the executable
mv "$INSTALL_DIR/bin/valgrind" "$INSTALL_DIR/bin valgrind_varlat"

# Add valgrind_varlat to PATH
echo "export PATH=\"$INSTALL_DIR/bin:\$PATH\"" >> ~/.bashrc
source ~/.bashrc
```

## Algorithm Testing
Because of how many warnings are output, it is not feasible to store all the warnings in terms of memory and runtime. Therefore, the `on_liboqs.sh` script handles ValgrindVarlat's output as follows:
- Since the suppression block (the data inside the curly braces {...}) contains the overall information of the issue, each unique block will be logged into the log file for the sake of simplicity.
- These unique blocks will be the ones counted as warnings, since the same warning may be output several times throughout the execution.

The testing framework currently disregarding all SPHINCS, ML-DSA tests due to the execessive length of time they require to execute.