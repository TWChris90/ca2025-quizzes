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
    li   a0, 0xC0C0          # A = -6.0
    li   a1, 0x4000          # B =  2.0
    jal  ra, bf16_div        # a0 = A / B
    li   t1, 0xC040          # expected = -3.0
    bne  a0, t1, test1_fail
    jal  ra, print_pass
    j    test2
test1_fail:
    jal  ra, print_fail
    j    test2
test2:
    li   a0, 0x3F80          # A =  1.0
    li   a1, 0xC080          # B = -4.0
    jal  ra, bf16_div
    li   t1, 0xBE80          # expected = -0.25
    bne  a0, t1, test2_fail
    jal  ra, print_pass
    j    test3
test2_fail:
    jal  ra, print_fail
    j    test3
test3:
    li   a0, 0x7F80          # A = +Inf
    li   a1, 0x4080          # B = 4.0
    jal  ra, bf16_div
    li   t1, 0x7F80          # expected = +Inf
    bne  a0, t1, test3_fail
    jal  ra, print_pass
    j    tests_done
test3_fail:
    jal  ra, print_fail
    j    tests_done
print_pass:
    la   a0, pass_msg
    li   a7, 4               # print string
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
    li   a7, 10              # exit
    ecall
    .globl bf16_isnan
bf16_isnan:
    li   t0, 0x7F80          # exponent mask
    and  t1, a0, t0
    bne  t1, t0, isnan_false # if (exp != 0xFF) ¡÷ not NaN/Inf
    li   t2, 0x007F          # mantissa mask
    and  t3, a0, t2          # t3 = mantissa
    snez a0, t3              # a0 = (mant != 0) ? 1 : 0
    ret
isnan_false:
    li   a0, 0               # return 0
    ret
    .globl bf16_isinf
bf16_isinf:
    li   t0, 0x7F80          # exponent mask
    and  t1, a0, t0
    bne  t1, t0, isinf_false # if (exp != 0xFF) ¡÷ not Inf/NaN
    li   t2, 0x007F          # mantissa mask
    and  t3, a0, t2          # t3 = mantissa
    seqz a0, t3              # a0 = (mant == 0) ? 1 : 0
    ret
isinf_false:
    li   a0, 0
    ret
    .globl bf16_iszero
bf16_iszero:
    li   t0, 0x7FFF          # mask out sign
    and  t1, a0, t0
    seqz a0, t1              # a0 = (bits_without_sign == 0) ? 1 : 0
    ret
   .globl f32_to_bf16
f32_to_bf16:
    addi sp, sp, -4
    sw   s0, 0(sp)
    mv   s0, a0
   srli t0, s0, 23
    andi t0, t0, 0xFF
    li   t1, 0xFF
    bne  t0, t1, unspecial
    srli a0, s0, 16
    li   t0, 0xFFFF
    and  a0, a0, t0
    j    f32_to_bf16_done
unspecial:
    srli t0, s0, 16
    andi t0, t0, 1           # low bit for tie-to-even
    li   t1, 0x7FFF
    add  t0, t0, t1          # t0 = 0x7FFF or 0x8000
    add  s0, s0, t0
    srli a0, s0, 16          # take high 16 bits as bf16
f32_to_bf16_done:
    lw   s0, 0(sp)
    addi sp, sp, 4
    ret
    .globl bf16_to_f32
bf16_to_f32:
    slli a0, a0, 16          # place bf16 in high 16 bits of f32
    ret
    .globl BF16_NAN
BF16_NAN:
    li   a0, 0x7FC0          # canonical NaN
    ret
    .globl BF16_ZERO
BF16_ZERO:
    li   a0, 0x0000          # +0
    ret
    .globl bf16_div
bf16_div:
    addi sp, sp, -16
    sw   s0, 0(sp)
    sw   s1, 4(sp)
    sw   s2, 8(sp)
    sw   s3, 12(sp)
    srli t0, a0, 15
    andi t0, t0, 1            # sign_a
    srli t1, a1, 15
    andi t1, t1, 1            # sign_b
    srli t2, a0, 7
    andi t2, t2, 0xFF         # exp_a
    srli t3, a1, 7
    andi t3, t3, 0xFF         # exp_b
    andi t4, a0, 0x7F         # mant_a (7 bits)
    andi t5, a1, 0x7F         # mant_b (7 bits)
    xor  s0, t0, t1           # s0 = result_sign
    li   t6, 0xFF             # common constant
    bne  t3, t6, check_zero   # if exp_b != 0xFF
    beqz t5, check_inf        # mant_b == 0 ¡÷ Inf
    mv   a0, a1               # b is NaN ¡÷ return b
    j    recover
check_inf:
   bne  t2, t6, result_sign_1
    bnez t4, result_sign_1    # a is NaN
    li   a0, 0x7FC0           # Inf / Inf ¡÷ NaN
    j    recover
result_sign_1:
    # return signed zero (finite / Inf ¡÷ 0)
    slli a0, s0, 15
    j    recover
check_zero:
    bnez t3, check_2_inf      # if exp_b != 0 ¡÷ not zero
    bnez t5, check_2_inf      # mant_b != 0 ¡÷ subnormal
    bnez t2, result_sign_2    # if a != 0 ¡÷ Inf with sign
    bnez t4, result_sign_2    # a subnormal non-zero
    li   a0, 0x7FC0           # 0 / 0 ¡÷ NaN
    j    recover    
result_sign_2:
    # division by zero ¡÷ signed Inf
    slli a0, s0, 15
    li   t6, 0x7F80
    or   a0, a0, t6
    j    recover
check_2_inf:
    bne  t2, t6, check_div_zero
    beqz t4, result_3         # a is Inf (mant == 0)
    mv   a0, a0               # a is NaN ¡÷ return a
    j    recover
result_3:
    # a is Inf, b finite non-zero ¡÷ signed Inf
    slli a0, s0, 15
    li   t6, 0x7F80
    or   a0, a0, t6
    j    recover
check_div_zero:
    bnez t2, norm             # exp_a != 0 ¡÷ not zero
    bnez t4, norm             # mant_a != 0 ¡÷ not zero
    slli a0, s0, 15           # 0 / non-zero ¡÷ signed zero
    j    recover
norm:
    beqz t2, norm_b
    ori  t4, t4, 0x80         # mant_a |= 1 << 7
norm_b:
    beqz t3, norm_end
    ori  t5, t5, 0x80         # mant_b |= 1 << 7
norm_end:
    slli s1, t4, 15           # s1: dividend = mant_a << 15
    mv   s2, t5               # s2: divisor  = mant_b
    li   s3, 0                # s3: quotient = 0
    li   t6, 0                # loop counter i = 0
div_loop:
    li   a2, 16
    bge  t6, a2, end_div_loop # while (i < 16)
    slli s3, s3, 1            # quotient <<= 1
    li   a3, 15
    sub  a3, a3, t6           # shift = 15 - i
    sll  a4, s2, a3           # (divisor << (15 - i))
    bltu s1, a4, skip_sub     # if dividend < shifted divisor ¡÷ skip
    sub  s1, s1, a4           # dividend -= shifted divisor
    ori  s3, s3, 1            # quotient |= 1
skip_sub:
    addi t6, t6, 1            # i++
    j    div_loop
end_div_loop:
    sub  a2, t2, t3           # a2 = exp_a - exp_b
    addi a2, a2, 127          # + BF16_EXP_BIAS
    bnez t2, res_b
    addi a2, a2, -1           # if a subnormal, exponent--
res_b:
    bnez t3, q_check
    addi a2, a2, 1            # if b subnormal, exponent++
q_check:
    li   t6, 0x8000
    and  a4, s3, t6           # check highest bit of quotient
    beqz a4, q_else
    srli s3, s3, 8
    j    check_overflow
q_else:
q_loop:
    li   t6, 0x8000
    and  a4, s3, t6
    bnez a4, q_loop_done      # stop when MSB becomes 1
    li   t6, 1
    ble  a2, t6, q_loop_done  # avoid exponent going below 1
    slli s3, s3, 1            # shift mantissa left
    addi a2, a2, -1           # exponent--
    j    q_loop
q_loop_done:
    srli s3, s3, 8            # keep top 8 bits (1.xxx)
check_overflow:
    andi s3, s3, 0x7F         # keep 7-bit mantissa
    li   t6, 0xFF
    blt  a2, t6, check_un
   slli a0, s0, 15
    li   t6, 0x7F80
    or   a0, a0, t6
    j    recover
check_un:
    bgt  a2, x0, final_result # exponent > 0 ¡÷ normal number
    slli a0, s0, 15
    j    recover
final_result:
    slli a0, s0, 15           # sign
    andi a2, a2, 0xFF
    slli a2, a2, 7            # exponent
    or   a0, a0, a2
    andi s3, s3, 0x7F         # mantissa
    or   a0, a0, s3
recover:
    lw   s0, 0(sp)
    lw   s1, 4(sp)
    lw   s2, 8(sp)
    lw   s3, 12(sp)
    addi sp, sp, 16
    ret
