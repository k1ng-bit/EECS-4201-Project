# sb-burst-compute: rounds of "a burst of stores, then ALU work".
#
# This is the store buffer's best case (Stage 4 plan, decision 7): the stores
# of a burst enter the SB in one cycle each, and the SB writes them to memory
# while the ALU loop runs. It also shows the size trade-off:
#   - a burst longer than the SB depth fills it, and the extra stores wait;
#   - entries beyond the burst length never fill and buy nothing.
#
# BURST (stores per round) is set when assembling, for example
#   riscv64-unknown-elf-as --defsym BURST=8 ...
# build.sh makes sb-burst-compute-b2, -b4, -b8 and -b16.
#
# Pass: x1 = 1 at ecall. Fail: x1 = 0 (top_tb checks x1).

    .ifndef BURST
    .equ BURST, 8               # stores per round
    .endif
    .equ ROUNDS, 8              # burst + compute rounds
    .equ COMPUTE, 100           # ALU loop iterations after each burst

    .section .text.init
    .globl _start
_start:
    li   x1, 0                  # result stays 0 until every check passes
    lui  x10, 0x1001            # x10 = 0x01001000: data area after the program
    li   x20, ROUNDS            # round counter, also the value each round stores
    li   x22, 0                 # running sum computed by the ALU loop

round:
    # The burst: BURST stores of the round number, back to back
    .set offset, 0
    .rept BURST
    sw   x20, offset(x10)
    .set offset, offset + 4
    .endr

    # ALU work while the SB writes the burst to memory
    li   x21, COMPUTE
compute:
    add  x22, x22, x21
    addi x21, x21, -1
    bnez x21, compute

    addi x20, x20, -1
    bnez x20, round

    # Every slot holds the last round's value, 1
    li   x7, 1
    .set offset, 0
    .rept BURST
    lw   x6, offset(x10)
    bne  x6, x7, fail
    .set offset, offset + 4
    .endr

    # The ALU sum is ROUNDS * (1 + 2 + ... + COMPUTE)
    li   x7, ROUNDS * COMPUTE * (COMPUTE + 1) / 2
    bne  x22, x7, fail

    li   x1, 1                  # every check passed
fail:
    ecall
    nop
    nop
    nop
    nop
