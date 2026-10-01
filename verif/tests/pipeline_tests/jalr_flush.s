.include "daksh_common.inc"
.section .text.init
.globl _start

_start:
    la x10, guard
    addi x20, x0, 0
    addi x7, x0, 99

    # JALR must clear target bit zero.
    la x5, target
    ori x5, x5, 1
    jalr x6, 0(x5)

link_address:
    # These wrong-path instructions must not commit.
    sw x7, 0(x10)
    addi x20, x0, 99

target:
    # Saved return address must equal JALR PC + 4.
    la x8, link_address
    bne x6, x8, fail

    bne x20, x0, fail
    lw x9, 0(x10)
    bne x9, x0, fail

    finish_test

.section .data
.balign 4
guard:
    .word 0
