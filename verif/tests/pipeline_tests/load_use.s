.include "daksh_common.inc"
.section .text.init
.globl _start

_start:
    la x10, data

    # Immediate load-to-ALU dependency.
    lw x5, 0(x10)
    addi x6, x5, 7

    # Expected: 41 + 7 = 48.
    addi x7, x0, 48
    bne x6, x7, fail

    # Repeat with a negative loaded value.
    lw x8, 4(x10)
    add x9, x8, x6

    # Expected: -3 + 48 = 45.
    addi x7, x0, 45
    bne x9, x7, fail

    finish_test

.section .data
.balign 4
data:
    .word 41
    .word -3
