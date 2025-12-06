.globl bf16_isinf
bf16_isinf:
    lui   t0, 0x7            # Load upper bits ¡÷ 0x00007000
    addi  t0, t0, 0x780      # Add lower part (within 12-bit range)
    addi  t0, t0, 0x80       # Now t0 = 0x00007F80
    and   t1, a0, t0         # Extract exponent field: t1 = a0 & 0x7F80
    bne   t1, t0, isinf_false # If exponent != 0xFF ¡÷ not Inf/NaN
    andi  t3, a0, 0x7F       # Isolate mantissa bits (lowest 7)
    sltiu a0, t3, 1
    ret
isinf_false:
    addi  a0, x0, 0          # Return 0 if not infinity
    ret
