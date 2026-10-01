# RV32I only; do not compress or relax instructions.
.option norvc
.option norelax

# Completion: x31 = 1 means success; x31 = 2 means failure.
.macro finish_test
    j pass
fail:
    addi x31, x0, 2
1:
    j 1b
pass:
    addi x31, x0, 1
2:
    j 2b
.endm
