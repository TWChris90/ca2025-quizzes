f32_to_bf16:
    addi  sp, sp, -4
    sw    s0, 0(sp)
    addi  s0, a0, 0             # Save input (float32 bits) to s0
    srli  t0, s0, 23
    andi  t0, t0, 0xFF
    addi  t1, x0, 0xFF
    bne   t0, t1, unspecial     # If exp != 255 ¡÷ normal number
    srli  a0, s0, 16
    lui   t0, 0x1               # t0 = 0x00010000
    addi  t0, t0, -1            # t0 = 0x0000FFFF
    and   a0, a0, t0            # Mask lower 16 bits
    jal   x0, f32_to_bf16_done  # Jump to end
unspecial:
    srli  t0, s0, 16
    andi  t0, t0, 1             # t0 = LSB of the upper 16 bits
    lui   t1, 0x8               # t1 = 0x00008000
    addi  t1, t1, -1            # t1 = 0x00007FFF
    add   t0, t0, t1            # Add rounding offset (0x7FFF + LSB)
    add   s0, s0, t0            # Apply rounding to full 32-bit value
    srli  a0, s0, 16            # Take upper 16 bits as bfloat16 result
f32_to_bf16_done:
    lw    s0, 0(sp)
    addi  sp, sp, 4
    ret
