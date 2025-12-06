.data
pass_msg:   .asciz "Test Passed\n"
fail_msg:   .asciz "Test Failed\n"
.text
.globl main
.globl bf16_sqrt
main:
    addi sp, sp, -4
    sw   ra, 0(sp)
test1:
    li   a0, 0x3F80          # A = 1.0
    jal  ra, bf16_sqrt       # a0 = sqrt(A)
    li   t1, 0x3F80          # expected = 1.0
    bne  a0, t1, test1_fail
    jal  ra, print_pass
    j    test2
test1_fail:
    jal  ra, print_fail
    j    test2
test2:
    li   a0, 0x3E80          # A = 0.25
    jal  ra, bf16_sqrt
    li   t1, 0x3F00          # expected = 0.5
    bne  a0, t1, test2_fail
    jal  ra, print_pass
    j    test3
test2_fail:
    jal  ra, print_fail
    j    test3
test3:
    li   a0, 0x7F80          # A = +Inf
    jal  ra, bf16_sqrt
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
bf16_sqrt:
    addi sp, sp, -32
    sw   ra, 28(sp)
    sw   s0, 24(sp)
    sw   s1, 20(sp)
    sw   s2, 16(sp)
    sw   s3, 12(sp)
    sw   s4,  8(sp)
    sw   s5,  4(sp)
    sw   s6,  0(sp)
    srli t0, a0, 15          # t0 = sign bit
    andi t0, t0, 1
    srli t1, a0, 7           # t1 = exponent (8 bits)
    andi t1, t1, 0xFF
    andi t2, a0, 0x7F        # t2 = mantissa (7 bits)
    li   t3, 0xFF
    bne  t1, t3, check_zero  # if exponent != 0xFF ¡÷ not Inf/NaN
    bnez t2, return_a        # mantissa != 0 ¡÷ NaN, just return a
    bnez t0, return_nan      # negative Inf ¡÷ sqrt is NaN
    j    return_a            # +Inf ¡÷ sqrt(+Inf) = +Inf
check_zero:
    or   t3, t1, t2          # if exponent==0 and mantissa==0 ¡÷ zero
    bnez t3, check_negative
    j    return_zero
check_negative:
    bnez t0, return_nan      # negative finite number ¡÷ NaN
    bnez t1, compute_sqrt    # if exponent != 0 ¡÷ normal value
    j    return_zero         # subnormal very close to 0 ¡÷ treat as 0
compute_sqrt:
    addi s0, t1, -127        # s0 = exp - bias
    ori  s1, t2, 0x80        # normalized mantissa with implicit 1
    andi t3, s0, 1
    beqz t3, even_exp
    slli s1, s1, 1           # make mantissa bigger for odd exponent
    addi t4, s0, -1
    srai t4, t4, 1           # (exp - 1) / 2
    addi s2, t4, 127         # s2 = result exponent (biased)
    j    binary_search
even_exp:
    srai t4, s0, 1           # exp / 2
    addi s2, t4, 127         # s2 = result exponent (biased)
binary_search:
    li   s3, 90              # low bound (approx range)
    li   s4, 256             # high bound
    li   s5, 128             # best candidate mantissa
search_loop:
    bgt  s3, s4, search_done # while low <= high
    add  t3, s3, s4
    srli t3, t3, 1           # mid = (low + high) / 2
    mv   a1, t3              # multiply mid * mid using shift-add
    mv   a2, t3
    jal  ra, multiply        # result in a0
    mv   t4, a0              # t4 = mid^2
    srli t4, t4, 7           # align to compare with s1
    bgt  t4, s1, search_high # if mid^2 > mantissa ¡÷ go left
    mv   s5, t3              # mid is new best
    addi s3, t3, 1           # low = mid + 1
    j    search_loop
search_high:
    addi s4, t3, -1          # high = mid - 1
    j    search_loop
search_done:
    li   t3, 256
    blt  s5, t3, check_low   # if s5 < 256 ¡÷ maybe need left shift
    srli s5, s5, 1           # s5 >= 256 ¡÷ shift right once and increment exponent
    addi s2, s2, 1
    j    extract_mant
check_low:
    li   t3, 128
    bge  s5, t3, extract_mant
norm_loop:
    li   t3, 128
    bge  s5, t3, extract_mant # stop when MSB is at bit 7
    li   t3, 1
    ble  s2, t3, extract_mant # avoid exponent underflow
    slli s5, s5, 1
    addi s2, s2, -1
    j    norm_loop
extract_mant:
    andi s6, s5, 0x7F        # keep 7-bit mantissa
    li   t3, 0xFF
    bge  s2, t3, return_inf  # overflow exponent ¡÷ +Inf
    blez s2, return_zero     # exponent <= 0 ¡÷ treat as 0
    andi t3, s2, 0xFF        # final exponent
    slli t3, t3, 7
    or   a0, t3, s6          # pack exponent + mantissa (sign is 0)
    j    cleanup
return_zero:
    li   a0, 0x0000          # +0
    j    cleanup
return_nan:
    li   a0, 0x7FC0          # canonical NaN
    j    cleanup
return_inf:
    li   a0, 0x7F80          # +Inf
    j    cleanup
return_a:
    j    cleanup             # just return the original a0
cleanup:
    lw   s6, 0(sp)
    lw   s5, 4(sp)
    lw   s4, 8(sp)
    lw   s3, 12(sp)
    lw   s2, 16(sp)
    lw   s1, 20(sp)
    lw   s0, 24(sp)
    lw   ra, 28(sp)
    addi sp, sp, 32
    ret
multiply:
    li   a0, 0                # a0 = result = 0
    beqz a2, mult_done        # if multiplier == 0 ¡÷ return 0
mult_loop:
    andi t0, a2, 1            # if (a2 & 1) add a1
    beqz t0, mult_skip
    add  a0, a0, a1
mult_skip:
    slli a1, a1, 1            # a1 <<= 1
    srli a2, a2, 1            # a2 >>= 1
    bnez a2, mult_loop        # loop while any bits remain
mult_done:
    ret
