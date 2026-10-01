.include "member3_common.inc"
.section .text.init
.globl _start

_start:
    # Zero intervening instructions.
    addi x5, x0, 10
    addi x6, x5, 1

    # One intervening instruction.
    addi x7, x0, 20
    nop
    addi x8, x7, 2

    # Two intervening instructions: WB/ID timing.
    addi x9, x0, 30
    nop
    nop
    addi x10, x9, 3

    # Three intervening instructions.
    addi x11, x0, 40
    nop
    nop
    nop
    addi x12, x11, 4

    # Consumer must observe the newest write.
    addi x13, x0, 3
    addi x13, x0, 4
    add x14, x13, x13

    addi x15, x0, 11
    bne x6, x15, fail
    addi x15, x0, 22
    bne x8, x15, fail
    addi x15, x0, 33
    bne x10, x15, fail
    addi x15, x0, 44
    bne x12, x15, fail
    addi x15, x0, 8
    bne x14, x15, fail

    finish_test
