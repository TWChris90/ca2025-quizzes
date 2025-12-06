.globl bf16_isnan
bf16_isnan:
    lui  t0, 0x7
    addi t0, t0, 0x780  # t0 = 0x00007780
    addi t0, t0, 0x80   # t0 = 0x00007F80
    and  t1, a0, t0
    bne  t1, t0, isnan_false   # if (exp != 0xFF) ¡÷ not NaN/Inf
    andi t3, a0, 0x7F          # t3 = mantissa
    sltu a0, x0, t3
    ret
isnan_false:
    addi a0, x0, 0
    ret
