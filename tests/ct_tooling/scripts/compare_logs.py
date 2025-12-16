# SPDX-License-Identifier: MIT

#!/usr/bin/env python3

"""
Compare { ... } blocks between two log files.

Output:
  - Blocks only in file A
  - Blocks only in file B
  - Blocks present in both

Usage:
  python3 scripts/compare_blocks.py [--out-dir outdir] [--tool-a toolaname] [--tool-b toolbname] fileA.log fileB.log

Options:
  --out-dir DIR : if provided, write three files: only_in_a.txt, only_in_b.txt, in_both.txt
"""
import argparse
import hashlib
from pathlib import Path
import sys

def read_blocks(path):
    """Return list of raw block strings (including braces) found in file in order."""
    lines = path.read_text(encoding='utf-8', errors='replace').splitlines()
    blocks = []
    in_block = False
    cur = []
    for ln in lines:
        if not in_block and ln.strip() == '{':
            in_block = True
            cur = [ln]
            continue
        if in_block:
            cur.append(ln)
            if ln.strip() == '}':
                blocks.append('\n'.join(cur))
                in_block = False
                cur = []
    return blocks


def key_of_block(s):
    # trim trailing whitespace on each line to avoid trivial \r differences
    k = '\n'.join(line.rstrip() for line in s.splitlines())
    # hash to make comparisons efficient and avoid huge memory in sets (but keep mapping)
    h = hashlib.sha256(k.encode('utf-8')).hexdigest()
    return h, k

def group_by_hash(blocks):
    """Return dict: hash -> canonical text and list of occurrences (original texts)"""
    d = {}
    for b in blocks:
        h, canon = key_of_block(b)
        if h not in d:
            d[h] = {'canon': canon, 'occurrences': []}
        d[h]['occurrences'].append(b)
    return d

def write_group_to_file(path: Path, entries):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w', encoding='utf-8') as fh:
        if not entries:
            fh.write("(none)\n")
            return

        for i, txt in enumerate(entries, 1):
            fh.write(f"--- BLOCK {i} ---\n")
            fh.write(txt)
            fh.write("\n\n")

def main():
    p = argparse.ArgumentParser(description='Compare { ... } blocks between two files')

    p.add_argument('--out-dir', type=Path, help='Write results to files inside this directory')
    p.add_argument('--tool-a', type=str, help='Name of the tool used in file A')
    p.add_argument('--tool-b', type=str, help='Name of the tool used in file B')
    p.add_argument('a', type=Path, help='File A')
    p.add_argument('b', type=Path, help='File B')
    args = p.parse_args()

    if not args.a.exists() or not args.b.exists():
        print("One of the files does not exist", file=sys.stderr)
        sys.exit(2)

    a_blocks = read_blocks(args.a)
    b_blocks = read_blocks(args.b)

    a_map = group_by_hash(a_blocks)
    b_map = group_by_hash(b_blocks)

    a_hashes = set(a_map.keys())
    b_hashes = set(b_map.keys())

    only_a = sorted(a_hashes - b_hashes)
    only_b = sorted(b_hashes - a_hashes)
    in_both = sorted(a_hashes & b_hashes)

    def print_section(title, hashes_list, source_map):
        print("="*80)
        print(title)
        print("="*80)
        if not hashes_list:
            print("(none)\n")
            return
        for i, h in enumerate(hashes_list, 1):
            canon = source_map[h]['canon']
            print(f"--- {title} (block {i}) ---")
            print(canon)
            print()

    print(f"File A: {args.tool_a}  blocks found: {len(a_blocks)}  unique-by-key: {len(a_map)}")
    print(f"File B: {args.tool_b}  blocks found: {len(b_blocks)}  unique-by-key: {len(b_map)}")
    print()

    print_section(f"Warnings only in {args.tool_a}", only_a, a_map)
    print_section(f"Warnings only in {args.tool_b}", only_b, b_map)
    print_section("Common warnings to both tools", in_both, a_map)

    if args.out_dir:
        out = args.out_dir
        out.mkdir(parents=True, exist_ok=True)
        # For only-in-A and only-in-B write the canonical blocks (one per unique)
        only_a_texts = [a_map[h]['canon'] for h in only_a]
        only_b_texts = [b_map[h]['canon'] for h in only_b]
        both_texts = [a_map[h]['canon'] for h in in_both]
        write_group_to_file(out / f'only_in_{args.tool_a}.txt', only_a_texts)
        write_group_to_file(out / f'only_in_{args.tool_b}.txt', only_b_texts)
        write_group_to_file(out / 'in_both.txt', both_texts)

if __name__ == '__main__':
    main()