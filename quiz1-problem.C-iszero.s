.globl bf16_iszero
bf16_iszero:
    lui   t0, 0x8              # t0 = 0x00008000
    addi  t0, t0, -1           # t0 = 0x00007FFF
    and   t1, a0, t0           # t1 = a0 & 0x7FFF
    sltiu a0, t1, 1
    ret
