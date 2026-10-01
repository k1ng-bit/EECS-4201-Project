.include "member3_common.inc"
.section .text.init
.globl _start

_start:
    # Writes to x0 must be discarded.
    addi x0, x0, 123
    addi x5, x0, 7

    addi x0, x0, -1
    addi x6, x0, 9

    add x0, x0, x0
    addi x7, x0, 11

    nop
    nop
    nop

    # ADDI does not read rs2, even though immediate bits
    # occupy the same instruction positions as rs2.
    addi x8, x0, 17
    addi x9, x0, 8

    nop
    nop
    nop

    # Testbench independently checks the final values.
    addi x31, x0, 1
done:
    j done
