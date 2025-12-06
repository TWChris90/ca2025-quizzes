    .data
newline:    .string "\n"
pass_msg:   .asciz "Test Passed\n"
fail_msg:   .asciz "Test Failed\n"
    .text
    .globl main
main:
    addi sp, sp, -4
    sw   ra, 0(sp)
test1:
    li   a0, 0xC000          # A = -2.0
    li   a1, 0x3F00          # B = 0.5
    jal  ra, bf16_mul        # a0 = A * B
    li   t1, 0xBF80          # expected = -1.0
    bne  a0, t1, test1_fail
    jal  ra, print_pass
    j    test2
test1_fail:
    jal  ra, print_fail
    j    test2
test2:
    li   a0, 0xC040          # A = -3.0
    li   a1, 0xC080          # B = -4.0
    jal  ra, bf16_mul
    li   t1, 0x4140          # expected = 12.0
    bne  a0, t1, test2_fail
    jal  ra, print_pass
    j    test3
test2_fail:
    jal  ra, print_fail
    j    test3
test3:
    li   a0, 0x7F80          # A = +Inf
    li   a1, 0xC000          # B = -2.0
    jal  ra, bf16_mul
    li   t1, 0xFF80          # expected = -Inf
    bne  a0, t1, test3_fail
    jal  ra, print_pass
    j    tests_done
test3_fail:
    jal  ra, print_fail
    j    tests_done
print_pass:
    la   a0, pass_msg
    li   a7, 4               # syscall: print string
    ecall
    jr   ra
print_fail:
    la   a0, fail_msg
    li   a7, 4
    ecall
    jr   ra
tests_done:
    lw   ra, 0(sp)
    addi sp, sp, 4
    li   a7, 10              # syscall: exit
    ecall
    .globl bf16_mul
bf16_mul:
    addi sp, sp, -16
    sw   s0, 0(sp)
    sw   s1, 4(sp)
    sw   s2, 8(sp)
    sw   ra, 12(sp)
    srli t0, a0, 15              # sign_a = (a0 >> 15) & 1
    andi t0, t0, 1
    srli t1, a1, 15              # sign_b = (a1 >> 15) & 1
    andi t1, t1, 1
    srli t2, a0, 7               # exp_a = (a0 >> 7) & 0xFF
    andi t2, t2, 0xFF
    srli t3, a1, 7               # exp_b = (a1 >> 7) & 0xFF
    andi t3, t3, 0xFF
    andi t4, a0, 0x7F            # mant_a (7 bits)
    andi t5, a1, 0x7F            # mant_b (7 bits)
    xor  s0, t0, t1              # s0 = result_sign = sign_a XOR sign_b
    li   t6, 0xFF
    bne  t2, t6, check_b_exp     # exp_a != 255 ¡÷ not NaN/Inf
    bnez t4, return_a            # mant_a != 0 ¡÷ a is NaN ¡÷ return a
    bnez t3, result_inf_a        # a is Inf, b not Inf/NaN ¡÷ result Inf/NaN logic
    bnez t5, result_inf_a        # b is NaN ¡÷ go inf/NaN handler
    j    return_nan              # Inf * Inf ¡÷ NaN? (here choose NaN)
result_inf_a:
    slli a0, s0, 15
    li   t6, 0x7F80
    or   a0, a0, t6
    j    quit    
check_b_exp:
    li   t6, 0xFF
    bne  t3, t6, check_0         # exp_b != 255 ¡÷ not NaN/Inf
    bnez t5, return_b            # b is NaN ¡÷ return b
    bnez t2, result_inf_b        # b is Inf, a finite ¡÷ result Inf/NaN logic
    bnez t4, result_inf_b        # a is NaN ¡÷ go inf/NaN handler
    j    return_nan              # Inf * Inf ¡÷ NaN
result_inf_b:
    slli a0, s0, 15
    li   t6, 0x7F80
    or   a0, a0, t6
    j    quit
check_0:
    bnez t2, a_not_zero
    bnez t4, a_not_zero
    j    return_0
a_not_zero:
    bnez t3, norm_mant
    bnez t5, norm_mant
return_0:
    slli a0, s0, 15              # signed zero
    j    quit
norm_mant:
    li   s1, 0                   # s1: exp_adjust = 0
    bnez t2, norm_a_else         # if exp_a != 0 ¡÷ already normalized
norm_loop_a:
    andi t6, t4, 0x80            # check bit 7
    bnez t6, norm_loop_a_done
    slli t4, t4, 1               # shift mant_a left
    addi s1, s1, -1              # exp_adjust--
    j    norm_loop_a
norm_loop_a_done:
    li   t2, 1                   # treat as exponent = 1 for subnormal
    j    check_exp_b_norm
norm_a_else:
    ori  t4, t4, 0x80            # add implicit 1
check_exp_b_norm:
    bnez t3, else_norm_b         # if exp_b != 0 ¡÷ normalized
norm_loop_b:
    andi t6, t5, 0x80
    bnez t6, norm_b_done
    slli t5, t5, 1
    addi s1, s1, -1
    j    norm_loop_b
norm_b_done:
    li   t3, 1
    j    mul_mant
else_norm_b:
    ori  t5, t5, 0x80            # add implicit 1
mul_mant:
    li   s2, 0                   # s2 = product = 0
    li   t6, 8                   # 8 bits to process
mul_loop:
    andi t0, t5, 1               # if (t5 & 1) add t4 to product
    beqz t0, skip_add
    add  s2, s2, t4
skip_add:
    slli t4, t4, 1               # multiplicand <<= 1
    srli t5, t5, 1               # multiplier  >>= 1
    addi t6, t6, -1
    bnez t6, mul_loop
    add  t6, t2, t3
    addi t6, t6, -127
    add  t6, t6, s1
    mv   s1, t6                  # s1 = result_exp
    li   t6, 0x8000
    and  t6, s2, t6
    beqz t6, mult_else
    srli s2, s2, 8               # keep highest 8 bits after overflow
    andi s2, s2, 0x7F            # keep 7 LSBs, bit 7 is implicit 1
    addi s1, s1, 1
    j    check_exp_overflow
mult_else:
    srli s2, s2, 7
    andi s2, s2, 0x7F
check_exp_overflow:
    li   t6, 0xFF
    blt  s1, t6, underflow_check # if result_exp < 255 ¡÷ continue
    slli a0, s0, 15
    li   t6, 0x7F80
    or   a0, a0, t6
    j    quit
underflow_check:
    bgt  s1, x0, final  # if result_exp > 0 ¡÷ normal
    li   t6, -6
    blt  s1, t6, return_0_udflow # too small ¡÷ signed zero
    li   t6, 1
    sub  t6, t6, s1             # shift = 1 - result_exp
    srl  s2, s2, t6
    li   s1, 0
    j    final
zero_label:
    nop
return_0_udflow:
    slli a0, s0, 15             # signed zero
    j    quit    
final:
    slli a0, s0, 15             # sign
    andi s1, s1, 0xFF
    slli s1, s1, 7              # exponent
    andi s2, s2, 0x7F           # mantissa
    or   a0, a0, s1
    or   a0, a0, s2
    j    quit
return_a:
    j    quit
return_b:
    mv   a0, a1                 # return b (NaN)
    j    quit
return_nan:
    li   a0, 0x7FC0             # canonical NaN
    j    quit
quit:
    lw   s0, 0(sp)
    lw   s1, 4(sp)
    lw   s2, 8(sp)
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret
