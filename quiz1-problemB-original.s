    .data
msg1:    .asciz ": produces value "
msg2:    .asciz " but encodes back to "
msg3:    .asciz ": value "
msg4:    .asciz " <= previous_value "
msg5:    .asciz "All tests passed.\n"
msg6:    .asciz "Some tests failed.\n"
newline:.asciz "\n"
    .align 2
    .text
    .globl main
main:
    jal   ra, test            # run the full test
    beq   a0, x0, Not_pass    # a0==0 => failed
    la    a0, msg5            # print "All tests passed.\n"
    li    a7, 4
    ecall
    li    a7, 10              # exit(0)
    li    a0, 0
    ecall
Not_pass:
    la    a0, msg6            # print "Some tests failed.\n"
    li    a7, 4
    ecall
    li    a7, 10              # exit(1)
    li    a0, 1
    ecall
test:
    addi  sp, sp, -4
    sw    ra, 0(sp)                # test calls other functions
    addi  s11, x0, -1              # previous_value = -1
    li    s10, 1                   # pass = true
    li    s9,  0                   # code = 0
    li    s8,  256                 # end bound
For_2:
    add   a0, s9, x0               # a0 = code
    jal   ra, uf8_decode
    add   s7, a0, x0               # s7 = decoded value
    add   a0, s7, x0
    jal   ra, uf8_encode
    add   s6, a0, x0               # s6 = re-encoded code
test_if_1:
    beq   s9, s6, test_if_2
    mv    a0, s9                   # print code (hex)
    li    a7, 34
    ecall
    la    a0, msg1                 # ": produces value "
    li    a7, 4
    ecall
    mv    a0, s7                   # print decoded value (dec)
    li    a7, 1
    ecall
    la    a0, msg2                 # " but encodes back to "
    li    a7, 4
    ecall
    mv    a0, s6                   # print re-encoded code (hex)
    li    a7, 34
    ecall
    la    a0, newline
    li    a7, 4
    ecall
    li    s10, 0                   # pass = false
test_if_2:
    blt   s11, s7, after_if
    mv    a0, s9                   # offending code (hex)
    li    a7, 34
    ecall
    la    a0, msg3                 # ": value "
    li    a7, 4
    ecall
    mv    a0, s7                   # current value (dec)
    li    a7, 1
    ecall
    la    a0, msg4                 # " <= previous_value "
    li    a7, 4
    ecall
    mv    a0, s11                  # previous_value (hex)
    li    a7, 34
    ecall
    la    a0, newline
    li    a7, 4
    ecall
    li    s10, 0                   # pass = false
after_if:
    mv    s11, s7                  # update previous_value
    addi  s9,  s9, 1               # code++
    blt   s9,  s8, For_2
    mv    a0, s10                  # return pass flag
    lw    ra, 0(sp)
    addi  sp, sp, 4
    jr    ra
CLZ:
    li    a1, 32                   # n
    li    a2, 16                   # c
CLZ_loop:
    srl   a3, a0, a2               # y = x >> c
    beq   a3, x0, CLZ_skip
    sub   a1, a1, a2               # n -= c
    add   a0, a3, x0               # x  = y
CLZ_skip:
    srli  a2, a2, 1                # c >>= 1
    bne   a2, x0, CLZ_loop
    sub   a0, a1, a0               # return n - x
    jr    ra
uf8_decode:
    andi  a1, a0, 0x0F             # m = low 4 bits
    srli  a2, a0, 4                # e = high 4 bits
    li    a3, 15
    sub   a3, a3, a2               # a3 = 15 - e
    li    a4, 0x7FFF
    srl   a4, a4, a3               # a4 = (2^e - 1)
    slli  a4, a4, 4                # a4 = ((2^e - 1) * 16)
    sll   a3, a1, a2               # a3 = (m << e)
    add   a0, a3, a4               # value = offset + (m<<e)
    jr    ra
uf8_encode:
    addi  sp, sp, -4
    sw    ra, 0(sp)                # will call CLZ
    add   a7, a0, x0
    li    a1, 16
    blt   a7, a1, UE_RET           # if v < 16 ¡÷ exact in e=0
    add   a0, a7, x0
    jal   ra, CLZ                  # a0 = lz
    li    a1, 31
    sub   a1, a1, a0               # a1 = msb
    addi  a3, a1, -4               # tentative e
    slti  a2, a3, 0                # if e < 0 ¡÷ e = 0
    beq   a2, x0, enc_e_nonneg
    li    a3, 0
enc_e_nonneg:
    li    a2, 15                   # if e > 15 ¡÷ e = 15
    bge   a2, a3, enc_e_ok_clamp_hi
    li    a3, 15
enc_e_ok_clamp_hi:
    addi  a5, x0, 0                # base = 0
    addi  a6, x0, 0                # i = 0
enc_fw_recur:
    beq   a6, a3, enc_fw_done
    slli  a1, a5, 1                # a1 = base*2
    addi  a5, a1, 16               # base = base*2 + 16
    addi  a6, a6, 1
    j     enc_fw_recur
enc_fw_done:
enc_down_adjust:
    beq   a3, x0, enc_seek_up      # if e==0 stop downward adjust
    blt   a7, a5, enc_do_down
    j     enc_seek_up
enc_do_down:
    addi  a1, a5, -16
    srli  a5, a1, 1                # base = (base - 16) >> 1
    addi  a3, a3, -1               # e--
    j     enc_down_adjust
enc_seek_up:
    li    a2, 15
enc_up_loop:
    beq   a3, a2, enc_pack         # if e==15 stop
    slli  a1, a5, 1
    addi  a1, a1, 16               # a1 = next = base*2 + 16
    blt   a7, a1, enc_pack         # if v < next stop
    add   a5, a1, x0               # base = next
    addi  a3, a3, 1                # e++
    j     enc_up_loop
enc_pack:
    sub   a2, a7, a5
    srl   a2, a2, a3               # mantissa
    slli  a1, a3, 4
    or    a0, a1, a2
UE_RET:
    lw    ra, 0(sp)
    addi  sp, sp, 4
    jr    ra
