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
    li   a0, 0x4000          # A = 2.0
    li   a1, 0x3FC0          # B = 1.5
    jal  ra, bf16_sub        # a0 = A - B
    li   t1, 0x3F00          # expected = 0.5
    bne  a0, t1, test1_fail
    jal  ra, print_pass
    j    test2
test1_fail:
    jal  ra, print_fail
    j    test2    
test2:
    li   a0, 0xBF80          # A = -1.0
    li   a1, 0x4000          # B = 2.0
    jal  ra, bf16_sub
    li   t1, 0xC040          # expected = -3.0
    bne  a0, t1, test2_fail
    jal  ra, print_pass
    j    test3
test2_fail:
    jal  ra, print_fail
    j    test3    
test3:
    li   a0, 0x0000          # A = 0.0
    li   a1, 0xC000          # B = -2.0
    jal  ra, bf16_sub
    li   t1, 0x4000          # expected = 2.0
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
    .globl bf16_sub
bf16_sub:
    li   t0, 0x8000          # sign bit mask
    xor  a1, a1, t0          # flip sign of B ¡÷ -B
    j    bf16_add            # reuse bf16_add
    .globl bf16_add
bf16_add:
    # extract sign, exponent, mantissa
    srli t0, a0, 15            # t0 = sign_a
    srli t1, a1, 15            # t1 = sign_b
    srli t2, a0, 7             # t2 = exp_a
    andi t2, t2, 0xFF
    srli t3, a1, 7             # t3 = exp_b
    andi t3, t3, 0xFF
    andi t4, a0, 0x7F          # t4 = mant_a
    andi t5, a1, 0x7F          # t5 = mant_b    
    li   t6, 0xFF
    bne  t2, t6, check_exp_b   
exp_a_checkall:
    bnez t4, ret_a             # mant_a != 0 ¡÷ a is NaN
    bne  t3, t6, ret_a         # a is Inf, b finite ¡÷ return a
    bnez t5, return_b1         # b mant != 0 ¡÷ b is NaN
    bne  t0, t1, return_nan    # +Inf + -Inf ¡÷ NaN
return_b1:
    mv   a0, a1
    ret
return_nan:
    li   a0, 0x7FC0            # NaN
ret_a:
    ret
check_exp_b:
    beq  t3, t6, return_b2     # b is NaN/Inf
    j    check_0_a
return_b2:
    mv   a0, a1
    ret
check_0_a:
    bnez t2, check_0_b         # exp_a != 0 ¡÷ not zero
    bnez t4, check_0_b         # mant_a != 0 ¡÷ not zero
    mv   a0, a1                # a is zero
    ret
check_0_b:
    bnez t3, norm_a
    bnez t5, norm_a
    ret                        # b is zero ¡÷ return a
norm_a:
    beqz t2, norm_b
    ori  t4, t4, 0x80          # mant_a |= 1<<7
norm_b:
    beqz t3, end_check1
    ori  t5, t5, 0x80          # mant_b |= 1<<7
end_check1:
    addi sp, sp, -20
    sw   s0, 16(sp)            # exp_diff
    sw   s1, 12(sp)            # result_sign
    sw   s2,  8(sp)            # result_exp
    sw   s3,  4(sp)            # result_mant
    sw   s4,  0(sp)
    sub  s0, t2, t3            # s0 = exp_a - exp_b
    blez s0, diff_neg          # exp_a <= exp_b
    mv   s2, t2                # result_exp = exp_a    
    li   t6, 8
    bgt  s0, t6, return_a      # diff > 8 ¡÷ B too small
    srl  t5, t5, s0            # shift mant_b
    j    exp_done
diff_neg:
    bgez s0, diff_else         # exp_diff == 0
    mv   s2, t3                # result_exp = exp_b
    li   t6, -8
    bge  s0, t6, shift_a       # diff >= -8 ¡÷ shift A
    j    return_b3          
shift_a:
    neg  s4, s0
    srl  t4, t4, s4
    j    exp_done
diff_else:
    mv   s2, t2
    j    exp_done
return_a:
    lw   s0, 16(sp)
    lw   s1, 12(sp)
    lw   s2,  8(sp)
    lw   s3,  4(sp)
    lw   s4,  0(sp)
    addi sp, sp, 20
    ret
return_b3:
    lw   s0, 16(sp)
    lw   s1, 12(sp)
    lw   s2,  8(sp)
    lw   s3,  4(sp)
    lw   s4,  0(sp)
    addi sp, sp, 20
    mv   a0, a1
    ret
exp_done:
    bne  t0, t1, diff_sign     # sign differ ¡÷ subtraction
same_sign:
    mv   s1, t0                # result_sign
    add  s3, t4, t5            # result_mant
    andi t6, s3, 0x100         # overflow into bit 8?
    beqz t6, norm_end
    srli s3, s3, 1
    addi s2, s2, 1
    li   t6, 0xFF
    bge  s2, t6, overflow_inf
    j    norm_end
overflow_inf:
    lw   s0, 16(sp)
    lw   s1, 12(sp)
    lw   s2,  8(sp)
    lw   s3,  4(sp)
    lw   s4,  0(sp)
    addi sp, sp, 20    
    slli a0, s1, 15
    li   t6, 0x7F80            # Inf
    or   a0, a0, t6
    ret
diff_sign:
    bge  t4, t5, manta_ge_b
    mv   s1, t1                # |b| > |a| ¡÷ sign = sign_b
    sub  s3, t5, t4            # mant_b - mant_a
    j    mant_result
manta_ge_b:
    mv   s1, t0                # |a| >= |b| ¡÷ sign = sign_a
    sub  s3, t4, t5            # mant_a - mant_b
mant_result:
    beqz s3, return_zero    
norm_loop:
    andi t6, s3, 0x80
    bnez t6, norm_end      
    slli s3, s3, 1
    addi s2, s2, -1
    blez s2, return_zero
    j    norm_loop
norm_end:
    slli a0, s1, 15
    andi t0, s2, 0xFF
    slli t0, t0, 7
    or   a0, a0, t0
    andi t0, s3, 0x7F
    or   a0, a0, t0   
    lw   s0, 16(sp)
    lw   s1, 12(sp)
    lw   s2,  8(sp)
    lw   s3,  4(sp)
    lw   s4,  0(sp)
    addi sp, sp, 20
    ret
return_zero:
    lw   s0, 16(sp)
    lw   s1, 12(sp)
    lw   s2,  8(sp)
    lw   s3,  4(sp)
    lw   s4,  0(sp)
    addi sp, sp, 20 
    li   a0, 0x0000
    ret
