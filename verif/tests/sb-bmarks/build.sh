#!/usr/bin/env bash
# Builds the store buffer test programs into .x memory images (one 32-bit hex
# word per line) and .d listings, the same way paradoxtests/run_tests.py does.
# Needs the RISC-V binutils: riscv64-unknown-elf-as, -ld, -objcopy, -objdump.
# Run from anywhere: bash verif/tests/sb-bmarks/build.sh
set -euo pipefail
cd "$(dirname "$0")"
LINK=../../paradoxtests/link.ld

# build <output name> <source> [assembler flags]
build() {
    out=$1; src=$2; shift 2
    riscv64-unknown-elf-as -march=rv32i -mabi=ilp32 "$@" -o "$out.o" "$src"
    riscv64-unknown-elf-ld -m elf32lriscv --no-relax -T "$LINK" -o "$out.elf" "$out.o"
    riscv64-unknown-elf-objcopy -O binary "$out.elf" "$out.bin"
    od -An -v -tx4 -w4 "$out.bin" | tr -d ' ' > "$out.x"
    riscv64-unknown-elf-objdump -d "$out.elf" | sed -n '/<_start>:/,$p' > "$out.d"
    rm -f "$out.o" "$out.elf" "$out.bin"
    echo "Built $out.x"
}

build sb-store-load sb-store-load.s
build sb-burst sb-burst.s
for burst in 2 4 8 16; do
    build "sb-burst-compute-b$burst" sb-burst-compute.s --defsym BURST=$burst
done
