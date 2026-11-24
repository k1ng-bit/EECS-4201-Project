# sb-store-load: every load-search outcome of the store buffer (SB).
#
# Each load below reads a word that a store before it has just written, so the
# store is usually still waiting in the SB (lec10 "Load Execute"):
#   1) sw then lw, same word          -> forward
#   2) two stores to one word, lw     -> forward the youngest store
#   3) sw then lb/lbu/lh/lhu          -> forward a subset, sign/zero extended
#   4) sw, then sb inside it, then lw -> partial match: interlock, read memory
#   5) sw, then sb to another byte,
#      lbu of a third byte            -> the newer sb does not overlap, so the
#                                        older sw forwards
#   6) sh then lh                     -> forward a halfword, sign extended
#   7) lw of a word never stored      -> no match: read memory
#   8) after a delay, lw of each word -> the head writes left the right bytes
#
# Pass: x1 = 1 at ecall. Fail: x1 = 0 (top_tb checks x1).

    .section .text.init
    .globl _start
_start:
    li   x1, 0                  # result stays 0 until every check passes
    lui  x10, 0x1001            # x10 = 0x01001000: data area after the program

    # 1) sw then lw: forward
    li   x5, 0x12345678
    sw   x5, 0(x10)
    lw   x6, 0(x10)
    bne  x6, x5, fail

    # 2) two stores to the same word: the youngest wins
    li   x5, 0x0badf00d
    sw   x5, 0(x10)
    li   x7, 0x600dcafe
    sw   x7, 0(x10)
    lw   x6, 0(x10)
    bne  x6, x7, fail

    # 3) sw then byte and halfword loads: bytes are 01 7f ff 80 at +4..+7
    li   x5, 0x80ff7f01
    sw   x5, 4(x10)
    lb   x6, 7(x10)             # 0x80 sign-extended
    li   x7, 0xffffff80
    bne  x6, x7, fail
    lbu  x6, 6(x10)             # 0xff zero-extended
    li   x7, 0x000000ff
    bne  x6, x7, fail
    lh   x6, 6(x10)             # 0x80ff sign-extended
    li   x7, 0xffff80ff
    bne  x6, x7, fail
    lhu  x6, 4(x10)             # 0x7f01 zero-extended
    li   x7, 0x00007f01
    bne  x6, x7, fail

    # 4) sb inside an older sw, then lw: partial match
    li   x5, 0x11223344
    sw   x5, 8(x10)
    li   x5, 0xaa
    sb   x5, 9(x10)             # word becomes 0x1122aa44
    lw   x6, 8(x10)
    li   x7, 0x1122aa44
    bne  x6, x7, fail

    # 5) newer sb to byte 1, lbu of byte 2: the older sw forwards
    li   x5, 0x55667788
    sw   x5, 12(x10)
    li   x5, 0x99
    sb   x5, 13(x10)            # word becomes 0x55669988
    lbu  x6, 14(x10)            # byte 2 = 0x66
    li   x7, 0x66
    bne  x6, x7, fail

    # 6) sh then lh: forward a halfword
    li   x5, 0xfedc
    sh   x5, 18(x10)
    lh   x6, 18(x10)            # 0xfedc sign-extended
    li   x7, 0xfffffedc
    bne  x6, x7, fail

    # 7) a word no store wrote: no match, read memory (zero)
    lw   x6, 64(x10)
    bne  x6, x0, fail

    # 8) give the SB time to write every store, then read each word back
    li   x8, 100
delay:
    addi x8, x8, -1
    bnez x8, delay
    lw   x6, 0(x10)
    li   x7, 0x600dcafe
    bne  x6, x7, fail
    lw   x6, 4(x10)
    li   x7, 0x80ff7f01
    bne  x6, x7, fail
    lw   x6, 8(x10)
    li   x7, 0x1122aa44
    bne  x6, x7, fail
    lw   x6, 12(x10)
    li   x7, 0x55669988
    bne  x6, x7, fail
    lw   x6, 16(x10)
    li   x7, 0xfedc0000
    bne  x6, x7, fail

    li   x1, 1                  # every check passed
fail:
    ecall
    nop
    nop
    nop
    nop
