.include "daksh_common.inc"
.section .text.init
.globl _start

_start:
    la x10, guard
    addi x20, x0, 0
    addi x5, x0, 1
    addi x6, x0, 1
    addi x7, x0, 99

    # Taken, following instructions not processed.
    beq x5, x6, taken
    sw x7, 0(x10)
    addi x20, x0, 99

taken:
    bne x20, x0, fail
    lw x8, 0(x10)
    bne x8, x0, fail

    # Not taken: both following instructions must execute.
    bne x5, x6, fail
    addi x21, x0, 7
    addi x22, x0, 9

    # Backward branch: taken twice, then not taken.
    addi x23, x0, 3
loop:
    addi x23, x23, -1
    bne x23, x0, loop

    addi x24, x0, 7
    bne x21, x24, fail
    addi x24, x0, 9
    bne x22, x24, fail

    finish_test

.section .data
.balign 4
guard:
    .word 0
