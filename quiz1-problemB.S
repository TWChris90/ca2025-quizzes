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
    .globl pb_main
pb_main:
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
    .globl test
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
    li      a1, 0              # count = 0
    add     a3, a0, x0         # a3 = x (working copy)
    srli    a2, a3, 16         # y = x >> 16
    bne     a2, x0, L1  # if y != 0, MSB in top half → keep y
    addi    a1, a1, 16         # else top 16 are zero
    j       L2
L1:
    add     a3, a2, x0         # a3 = y (keep top half)
L2:
    srli    a2, a3, 8          # y = a3 >> 8
    bne     a2, x0, L3   # if y != 0, MSB in this 8-bit window
    addi    a1, a1, 8          # else next 8 are zero
    j       L4
L3:
    add     a3, a2, x0         # a3 = y (keep this 8-bit window)
L4:
    li      a2, 7              # i = 7 .. 0
L5:
    blt     a2, x0, L_done    # i < 0 → done
    li      t0, 1
    sll     t0, t0, a2         # mask = 1 << i
    and     t0, t0, a3         # bit = a3 & mask
    bne     t0, x0, L_done    # first '1' found → stop
    addi    a1, a1, 1          # count++
    addi    a2, a2, -1         # i--
    j       L5
L_done:
    add     a0, a1, x0         # return count
    jr      ra
uf8_decode:
    andi  a1, a0, 0x0F             # m
    srli  a2, a0, 4                # e
    addi  a3, a2, 4                # e + 4
    li    a4, 1
    sll   a4, a4, a3               # 1 << (e+4)
    addi  a4, a4, -16              # offset
    sll   a3, a1, a2               # m << e
    add   a0, a3, a4               # value
    jr    ra
uf8_encode:
    addi  sp, sp, -4
    sw    ra, 0(sp)                # may call CLZ (software)
    add   a7, a0, x0               # a7 = value
    li    a1, 16
    blt   a7, a1, UE_RET            # value < 16 → return value
    add   a0, a7, x0               # call software CLZ
    jal   ra, CLZ
    li    a1, 31
    sub   a1, a1, a0               # a1 = msb = 31 - lz
    addi  a3, a1, -4
    slti  a2, a3, 0
    beqz  a2, 1f
    li    a3, 0
1:
    li    a2, 15
    ble   a3, a2, 2f
    li    a3, 15
2:
    addi  a4, a3, 4
    li    a5, 1
    sll   a5, a5, a4
    addi  a5, a5, -16              # a5 = offset0
    addi  a4, a3, 5
    li    a2, 1
    sll   a2, a2, a4
    addi  a2, a2, -16              # a2 = next
    blt   a7, a5, _dec_e           # value < offset0 → e = e0 - 1
    bge   a7, a2, _inc_e           # value >= next   → e = e0 + 1
    j     _e_ok                    # else e = e0
_dec_e:
    addi  a3, a3, -1
    bgez  a3, 3f
    li    a3, 0                    # e cannot go below 0
    li    a5, 0                    # offset(0) = 0
    j     4f
3:  # recompute offset(e) = (1 << (e+4)) - 16
    addi  a4, a3, 4
    li    a5, 1
    sll   a5, a5, a4
    addi  a5, a5, -16
4:
    j     _e_ok
_inc_e:
    addi  a3, a3, 1
    li    a1, 15
    ble   a3, a1, 5f
    li    a3, 15                  # e cannot exceed 15
5:  # recompute offset(e)
    addi  a4, a3, 4
    li    a5, 1
    sll   a5, a5, a4
    addi  a5, a5, -16
    j     _e_ok
_e_ok:
    sub   a2, a7, a5
    srl   a2, a2, a3              # mantissa = (value - offset) >> e
    slli  a1, a3, 4
    or    a0, a1, a2              # pack [eeee mmmm]
UE_RET:
    lw    ra, 0(sp)
    addi  sp, sp, 4
    jr    ra
