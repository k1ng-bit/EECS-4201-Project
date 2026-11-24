# sb-burst: a burst of 8 back-to-back stores (as many as the default SB depth).
#
# The values are prepared in registers first, so the 8 stores run back to
# back. Without a store buffer every store waits for memory. With it, the
# stores enter the SB and the pipeline keeps going (lec13 slide 65).
# The words are then read back twice:
#   - straight away, while the stores may still be in the SB (forward), and
#   - after a delay, when the SB has written them to memory.
#
# Pass: x1 = 1 at ecall. Fail: x1 = 0 (top_tb checks x1).

    .section .text.init
    .globl _start
_start:
    li   x1, 0                  # result stays 0 until every check passes
    lui  x10, 0x1001            # x10 = 0x01001000: data area after the program
    li   x11, 0x11111111        # the 8 values to store
    li   x12, 0x22222222
    li   x13, 0x33333333
    li   x14, 0x44444444
    li   x15, 0x55555555
    li   x16, 0x66666666
    li   x17, 0x77777777
    li   x18, 0x88888888

    # The burst: 8 stores back to back
    sw   x11, 0(x10)
    sw   x12, 4(x10)
    sw   x13, 8(x10)
    sw   x14, 12(x10)
    sw   x15, 16(x10)
    sw   x16, 20(x10)
    sw   x17, 24(x10)
    sw   x18, 28(x10)

    # Read back at once
    jal  x9, check

    # Let the SB write every store, then read back from memory
    li   x8, 100
delay:
    addi x8, x8, -1
    bnez x8, delay
    jal  x9, check

    li   x1, 1                  # every check passed
fail:
    ecall
    nop
    nop
    nop
    nop

# check: compares the 8 words with x11-x18. Returns through x9.
check:
    lw   x6, 0(x10)
    bne  x6, x11, fail
    lw   x6, 4(x10)
    bne  x6, x12, fail
    lw   x6, 8(x10)
    bne  x6, x13, fail
    lw   x6, 12(x10)
    bne  x6, x14, fail
    lw   x6, 16(x10)
    bne  x6, x15, fail
    lw   x6, 20(x10)
    bne  x6, x16, fail
    lw   x6, 24(x10)
    bne  x6, x17, fail
    lw   x6, 28(x10)
    bne  x6, x18, fail
    jalr x0, 0(x9)
