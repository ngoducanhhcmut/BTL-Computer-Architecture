# ================================================================
# WIENER FILTER - MIPS Assembly
# Course : Computer Architecture Lab (CO2008)
# Desc   : M=2 Wiener-Hopf optimal filter (MMSE criterion)
#
# Algorithm (M=2 Wiener-Hopf):
#   r0  = (1/N) * sum_{n=0}^{N-1}  x[n]^2
#   r1  = (1/N) * sum_{n=1}^{N-1}  x[n]*x[n-1]
#   gd0 = (1/N) * sum_{n=0}^{N-1}  d[n]*x[n]
#   gd1 = (1/N) * sum_{n=1}^{N-1}  d[n]*x[n-1]
#   det = r0^2 - r1^2
#   h0  = (r0*gd0 - r1*gd1) / det
#   h1  = (r0*gd1 - r1*gd0) / det
#   y[0]   = h0 * x[0]
#   y[n]   = h0*x[n] + h1*x[n-1]   (n=1..N-1)
#   MMSE   = (1/N) * sum (d[n]-y[n])^2
#
# Output format:
#   Filtered output:%8.4f%10.4f ... %10.4f\n
#   MMSE: %.4f\n
# ================================================================

.data

# ---- File names -----------------------------------------------
desired_fname:        .asciiz "desired.txt"
input_fname:          .asciiz "input.txt"
output_fname:         .asciiz "output.txt"

# ---- Named variables required by spec -------------------------
# FIX: .align 2 ensures 4-byte alignment for float arrays
.align 2
desired_signal:       .space 40        # 10 x float32
input_signal:         .space 40        # 10 x float32
optimize_coefficient: .space 8         # h0, h1  (M=2)
mmse:                 .float  0.0
output_signal:        .space 40        # 10 x float32

# ---- Internal counters ----------------------------------------
desired_n:            .word   0
input_n:              .word   0
out_fd:               .word  -1

# ---- Float constants ------------------------------------------
CONST_ZERO:           .float  0.0
CONST_ONE:            .float  1.0
CONST_HALF:           .float  0.5
CONST_TEN:            .float 10.0
CONST_10000:          .float 10000.0

# ---- String constants -----------------------------------------
STR_FILTERED:         .asciiz "Filtered output:"
STR_MMSE:             .asciiz "MMSE: "
STR_NEWLINE:          .asciiz "\n"
STR_SPACE:            .asciiz " "
STR_ERROR:            .asciiz "Error: size not match\n"

# ---- Working buffers ------------------------------------------
file_buf:             .space 512       # raw file content
num_buf:              .space 32        # float -> ASCII workspace

.text
.globl main

# ================================================================
# MAIN PROGRAM
# ================================================================
main:
    # -------- 1. Open and read desired.txt --------
    la   $a0, desired_fname
    li   $a1, 0                 # O_RDONLY
    li   $a2, 0
    li   $v0, 13                # syscall: open
    syscall
    bltz $v0, exit_program

    move $s0, $v0               # s0 = file descriptor

    move $a0, $s0
    la   $a1, file_buf
    li   $a2, 511
    li   $v0, 14                # syscall: read
    syscall
    move $s1, $v0               # s1 = bytes read

    bltz $s1, close_desired     # read error: still close fd
    la   $t0, file_buf
    add  $t0, $t0, $s1
    sb   $zero, 0($t0)          # null-terminate

close_desired:
    move $a0, $s0
    li   $v0, 16                # syscall: close
    syscall

    la   $a0, file_buf
    la   $a1, desired_signal
    la   $a2, desired_n
    jal  parse_floats

    # -------- 2. Open and read input.txt ----------
    la   $a0, input_fname
    li   $a1, 0
    li   $a2, 0
    li   $v0, 13
    syscall
    bltz $v0, exit_program

    move $s0, $v0

    move $a0, $s0
    la   $a1, file_buf
    li   $a2, 511
    li   $v0, 14
    syscall
    move $s1, $v0

    bltz $s1, close_input
    la   $t0, file_buf
    add  $t0, $t0, $s1
    sb   $zero, 0($t0)

close_input:
    move $a0, $s0
    li   $v0, 16
    syscall

    la   $a0, file_buf
    la   $a1, input_signal
    la   $a2, input_n
    jal  parse_floats

    # -------- 3. Size check -----------------------
    lw   $t0, desired_n
    lw   $t1, input_n
    bne  $t0, $t1, pr_size_err  # count mismatch → error

    # -------- 4-7. Compute filter & output --------
sizes_ok:
    beqz $t0, pr_size_err       # N=0: no data (avoids div-by-zero in compute_wiener)
    jal  compute_wiener
    jal  compute_output
    jal  compute_mmse

    # -------- 8. Open output.txt ------------------
    la   $a0, output_fname
    li   $a1, 1                 # O_WRONLY (MARS creates/truncates)
    li   $a2, 0
    li   $v0, 13
    syscall
    sw   $v0, out_fd

    # -------- 9. Print results --------------------
    jal  print_results

    # -------- 10. Close output.txt ----------------
    lw   $a0, out_fd
    li   $v0, 16
    syscall

    j    exit_program

    # -------- Error: size mismatch or N=0 ----------
pr_size_err:
    # Print error to console
    la   $a0, STR_ERROR
    li   $v0, 4
    syscall

    # Write error to output.txt
    la   $a0, output_fname
    li   $a1, 1                 # O_WRONLY (MARS creates/truncates)
    li   $a2, 0
    li   $v0, 13
    syscall
    bltz $v0, exit_program
    move $s0, $v0

    move $a0, $s0
    la   $a1, STR_ERROR
    li   $a2, 22                # len("Error: size not match\n")
    li   $v0, 15
    syscall

    move $a0, $s0
    li   $v0, 16
    syscall

exit_program:
    li   $v0, 10
    syscall


# ================================================================
# SUBROUTINE: parse_floats
#   $a0 = null-terminated ASCII buffer
#   $a1 = float32 output array
#   $a2 = &count  (word)
# ================================================================
parse_floats:
    move  $t8, $a0
    move  $t9, $a1
    move  $t7, $a2
    li    $t6, 0                # count

pf_next:
    lb    $t0, 0($t8)
    beqz  $t0, pf_done

    li    $t1, ' '
    beq   $t0, $t1, pf_skip
    li    $t1, 9
    beq   $t0, $t1, pf_skip
    li    $t1, 10
    beq   $t0, $t1, pf_skip
    li    $t1, 13
    beq   $t0, $t1, pf_skip
    j     pf_num

pf_skip:
    addiu $t8, $t8, 1
    j     pf_next

pf_num:
    # --- sign ---
    li    $t3, 0
    li    $t1, '-'
    bne   $t0, $t1, pf_int_part
    li    $t3, 1
    addiu $t8, $t8, 1
    lb    $t0, 0($t8)

pf_int_part:
    l.s   $f0, CONST_ZERO
    l.s   $f5, CONST_TEN

pf_int_loop:
    lb    $t0, 0($t8)
    li    $t1, '0'
    blt   $t0, $t1, pf_dot_check
    li    $t1, '9'
    bgt   $t0, $t1, pf_dot_check
    addiu $t0, $t0, -48
    mul.s $f0, $f0, $f5
    mtc1  $t0, $f1
    cvt.s.w $f1, $f1
    add.s $f0, $f0, $f1
    addiu $t8, $t8, 1
    j     pf_int_loop

pf_dot_check:
    li    $t1, '.'
    bne   $t0, $t1, pf_sign_apply
    addiu $t8, $t8, 1

    # FIX: scale = 1.0 / 10.0 = 0.1  (was wrong: 10/10 = 1.0)
    l.s   $f3, CONST_ONE        # f3 = 1.0
    l.s   $f4, CONST_TEN        # f4 = 10.0
    div.s $f3, $f3, $f4         # f3 = 0.1

pf_frac_loop:
    lb    $t0, 0($t8)
    li    $t1, '0'
    blt   $t0, $t1, pf_sign_apply
    li    $t1, '9'
    bgt   $t0, $t1, pf_sign_apply
    addiu $t0, $t0, -48
    mtc1  $t0, $f1
    cvt.s.w $f1, $f1
    mul.s $f4, $f1, $f3
    add.s $f0, $f0, $f4
    l.s   $f2, CONST_TEN
    div.s $f3, $f3, $f2         # scale /= 10
    addiu $t8, $t8, 1
    j     pf_frac_loop

pf_sign_apply:
    beqz  $t3, pf_store
    neg.s $f0, $f0

pf_store:
    li    $t1, 10
    bge   $t6, $t1, pf_done    # stop if array full (max 10 elements)
    s.s   $f0, 0($t9)
    addiu $t9, $t9, 4
    addiu $t6, $t6, 1
    j     pf_next

pf_done:
    sw    $t6, 0($t7)
    jr    $ra


# ================================================================
# SUBROUTINE: compute_wiener  (M=2 Wiener-Hopf)
# ================================================================
compute_wiener:
    addiu $sp, $sp, -4
    sw    $ra, 0($sp)

    lw    $t5, desired_n
    mtc1  $t5, $f20
    cvt.s.w $f20, $f20          # f20 = (float)N

    # --- r0 = (1/N) * sum x[n]^2 ---
    la    $t0, input_signal
    l.s   $f16, CONST_ZERO
    li    $t1, 0
cw_r0:
    bge   $t1, $t5, cw_r0_done
    l.s   $f0, 0($t0)
    mul.s $f0, $f0, $f0
    add.s $f16, $f16, $f0
    addiu $t0, $t0, 4
    addiu $t1, $t1, 1
    j     cw_r0
cw_r0_done:
    div.s $f16, $f16, $f20      # r0

    # --- r1 = (1/N) * sum x[n]*x[n-1], n=1..N-1 ---
    la    $t0, input_signal
    addiu $t0, $t0, 4           # x[1]
    la    $t2, input_signal     # x[0]
    l.s   $f17, CONST_ZERO
    li    $t1, 1
cw_r1:
    bge   $t1, $t5, cw_r1_done
    l.s   $f0, 0($t0)
    l.s   $f1, 0($t2)
    mul.s $f0, $f0, $f1
    add.s $f17, $f17, $f0
    addiu $t0, $t0, 4
    addiu $t2, $t2, 4
    addiu $t1, $t1, 1
    j     cw_r1
cw_r1_done:
    div.s $f17, $f17, $f20      # r1

    # --- gd0 = (1/N) * sum d[n]*x[n] ---
    la    $t0, desired_signal
    la    $t2, input_signal
    l.s   $f18, CONST_ZERO
    li    $t1, 0
cw_gd0:
    bge   $t1, $t5, cw_gd0_done
    l.s   $f0, 0($t0)
    l.s   $f1, 0($t2)
    mul.s $f0, $f0, $f1
    add.s $f18, $f18, $f0
    addiu $t0, $t0, 4
    addiu $t2, $t2, 4
    addiu $t1, $t1, 1
    j     cw_gd0
cw_gd0_done:
    div.s $f18, $f18, $f20      # gd0

    # --- gd1 = (1/N) * sum d[n]*x[n-1], n=1..N-1 ---
    la    $t0, desired_signal
    addiu $t0, $t0, 4           # d[1]
    la    $t2, input_signal     # x[0]
    l.s   $f19, CONST_ZERO
    li    $t1, 1
cw_gd1:
    bge   $t1, $t5, cw_gd1_done
    l.s   $f0, 0($t0)
    l.s   $f1, 0($t2)
    mul.s $f0, $f0, $f1
    add.s $f19, $f19, $f0
    addiu $t0, $t0, 4
    addiu $t2, $t2, 4
    addiu $t1, $t1, 1
    j     cw_gd1
cw_gd1_done:
    div.s $f19, $f19, $f20      # gd1

    # --- det = r0^2 - r1^2 ---
    mul.s $f21, $f16, $f16
    mul.s $f22, $f17, $f17
    sub.s $f21, $f21, $f22      # det

    # --- h0 = (r0*gd0 - r1*gd1) / det ---
    mul.s $f0, $f16, $f18
    mul.s $f1, $f17, $f19
    sub.s $f0, $f0, $f1
    div.s $f0, $f0, $f21        # h0

    # --- h1 = (r0*gd1 - r1*gd0) / det ---
    mul.s $f1, $f16, $f19
    mul.s $f2, $f17, $f18
    sub.s $f1, $f1, $f2
    div.s $f1, $f1, $f21        # h1

    la    $t0, optimize_coefficient
    s.s   $f0, 0($t0)           # h0
    s.s   $f1, 4($t0)           # h1

    lw    $ra, 0($sp)
    addiu $sp, $sp, 4
    jr    $ra


# ================================================================
# SUBROUTINE: compute_output
#   y[0] = h0*x[0]
#   y[n] = h0*x[n] + h1*x[n-1]
# ================================================================
compute_output:
    addiu $sp, $sp, -4
    sw    $ra, 0($sp)

    la    $t0, optimize_coefficient
    l.s   $f10, 0($t0)          # h0
    l.s   $f11, 4($t0)          # h1

    lw    $t5, desired_n
    la    $t1, input_signal
    la    $t2, output_signal

    # y[0] = h0 * x[0]
    l.s   $f0, 0($t1)
    mul.s $f0, $f10, $f0
    s.s   $f0, 0($t2)
    addiu $t1, $t1, 4
    addiu $t2, $t2, 4

    la    $t3, input_signal     # x[n-1], starts at x[0]
    li    $t4, 1

co_loop:
    bge   $t4, $t5, co_done
    l.s   $f0, 0($t1)           # x[n]
    l.s   $f1, 0($t3)           # x[n-1]
    mul.s $f0, $f10, $f0
    mul.s $f1, $f11, $f1
    add.s $f0, $f0, $f1
    s.s   $f0, 0($t2)
    addiu $t1, $t1, 4
    addiu $t2, $t2, 4
    addiu $t3, $t3, 4
    addiu $t4, $t4, 1
    j     co_loop

co_done:
    lw    $ra, 0($sp)
    addiu $sp, $sp, 4
    jr    $ra


# ================================================================
# SUBROUTINE: compute_mmse
#   MMSE = (1/N) * sum (d[n]-y[n])^2
# ================================================================
compute_mmse:
    addiu $sp, $sp, -4
    sw    $ra, 0($sp)

    lw    $t5, desired_n
    mtc1  $t5, $f2
    cvt.s.w $f2, $f2

    la    $t0, desired_signal
    la    $t1, output_signal
    l.s   $f0, CONST_ZERO
    li    $t2, 0

cm_loop:
    bge   $t2, $t5, cm_done
    l.s   $f3, 0($t0)
    l.s   $f4, 0($t1)
    sub.s $f3, $f3, $f4
    mul.s $f3, $f3, $f3
    add.s $f0, $f0, $f3
    addiu $t0, $t0, 4
    addiu $t1, $t1, 4
    addiu $t2, $t2, 1
    j     cm_loop

cm_done:
    div.s $f0, $f0, $f2
    s.s   $f0, mmse

    lw    $ra, 0($sp)
    addiu $sp, $sp, 4
    jr    $ra


# ================================================================
# SUBROUTINE: print_results
# ================================================================
print_results:
    addiu $sp, $sp, -28
    sw    $ra,  0($sp)
    sw    $s0,  4($sp)
    sw    $s1,  8($sp)
    sw    $s2, 12($sp)
    sw    $s3, 16($sp)
    sw    $s4, 20($sp)
    sw    $s5, 24($sp)

    lw    $s5, desired_n

    # "Filtered output:" to console and file
    la    $a0, STR_FILTERED
    li    $v0, 4
    syscall
    lw    $a0, out_fd
    la    $a1, STR_FILTERED
    li    $a2, 16
    li    $v0, 15
    syscall

    la    $s0, output_signal
    li    $s1, 0

pr_loop:
    bge   $s1, $s5, pr_done

    l.s   $f12, 0($s0)
    li    $s4, 10
    bnez  $s1, pr_go
    li    $s4, 8               # first value: width 8
pr_go:
    move  $a1, $s4
    jal   fmt_float_w

    addiu $s0, $s0, 4
    addiu $s1, $s1, 1
    j     pr_loop

pr_done:
    # newline
    la    $a0, STR_NEWLINE
    li    $v0, 4
    syscall
    lw    $a0, out_fd
    la    $a1, STR_NEWLINE
    li    $a2, 1
    li    $v0, 15
    syscall

    # "MMSE: " to console and file
    la    $a0, STR_MMSE
    li    $v0, 4
    syscall
    lw    $a0, out_fd
    la    $a1, STR_MMSE
    li    $a2, 6
    li    $v0, 15
    syscall

    # MMSE value (no field padding)
    l.s   $f12, mmse
    li    $a1, 0
    jal   fmt_float_w

    # newline
    la    $a0, STR_NEWLINE
    li    $v0, 4
    syscall
    lw    $a0, out_fd
    la    $a1, STR_NEWLINE
    li    $a2, 1
    li    $v0, 15
    syscall

    lw    $ra,  0($sp)
    lw    $s0,  4($sp)
    lw    $s1,  8($sp)
    lw    $s2, 12($sp)
    lw    $s3, 16($sp)
    lw    $s4, 20($sp)
    lw    $s5, 24($sp)
    addiu $sp, $sp, 28
    jr    $ra


# ================================================================
# SUBROUTINE: fmt_float_w
#   $f12 = value   $a1 = field_width (0=no padding)
#   Prints right-justified 4-decimal float to console+file.
#   Algorithm:
#     rounded_int = floor(|value|*10000 + 0.5)
#     int_part  = rounded_int / 10000
#     frac_part = rounded_int % 10000
#     string    = ['-'] int_digits '.' d3d2d1d0
#     pad left with spaces to fill field_width
# ================================================================
fmt_float_w:
    addiu $sp, $sp, -28
    sw    $ra,  0($sp)
    sw    $s0,  4($sp)
    sw    $s1,  8($sp)
    sw    $s2, 12($sp)
    sw    $s3, 16($sp)
    sw    $s4, 20($sp)
    sw    $s5, 24($sp)

    move  $s4, $a1              # field width

    # ---- Sign ----
    li    $s3, 0
    l.s   $f0, CONST_ZERO
    c.lt.s $f12, $f0
    bc1f  fw_pos
    li    $s3, 1
    neg.s $f12, $f12
fw_pos:

    # ---- rounded_int = floor(|val|*10000 + 0.5) ----
    l.s   $f1, CONST_10000
    mul.s $f2, $f12, $f1
    l.s   $f3, CONST_HALF
    add.s $f2, $f2, $f3
    floor.w.s $f4, $f2
    mfc1  $s0, $f4              # s0 = rounded_int

    # int_part / frac_part
    li    $t0, 10000
    div   $s0, $t0
    mflo  $s1                   # integer part
    mfhi  $s2                   # fractional digits 0000-9999

    # ---- Build string in num_buf ----
    la    $t5, num_buf
    li    $t6, 0                # byte count

    # sign
    beqz  $s3, fw_nosign
    li    $t0, '-'
    sb    $t0, 0($t5)
    addiu $t5, $t5, 1
    addiu $t6, $t6, 1
fw_nosign:

    # integer digits
    bnez  $s1, fw_int_nonzero
    li    $t0, '0'
    sb    $t0, 0($t5)
    addiu $t5, $t5, 1
    addiu $t6, $t6, 1
    j     fw_decimal

fw_int_nonzero:
    la    $t4, num_buf
    addiu $t4, $t4, 20          # temp buffer for reversed digits
    li    $t3, 0
    move  $t2, $s1
fw_dig_extract:
    beqz  $t2, fw_dig_reverse
    li    $t0, 10
    div   $t2, $t0
    mfhi  $t1
    mflo  $t2
    addiu $t1, $t1, '0'
    sb    $t1, 0($t4)
    addiu $t4, $t4, 1
    addiu $t3, $t3, 1
    j     fw_dig_extract

fw_dig_reverse:
    addiu $t4, $t4, -1
fw_rev_loop:
    beqz  $t3, fw_decimal
    lb    $t0, 0($t4)
    sb    $t0, 0($t5)
    addiu $t4, $t4, -1
    addiu $t5, $t5, 1
    addiu $t6, $t6, 1
    addiu $t3, $t3, -1
    j     fw_rev_loop

fw_decimal:
    li    $t0, '.'
    sb    $t0, 0($t5)
    addiu $t5, $t5, 1
    addiu $t6, $t6, 1

    # 4 fractional digits (d3 d2 d1 d0)
    move  $t2, $s2

    li    $t0, 1000
    div   $t2, $t0
    mflo  $t1
    mfhi  $t2
    addiu $t1, $t1, '0'
    sb    $t1, 0($t5)
    addiu $t5, $t5, 1
    addiu $t6, $t6, 1

    li    $t0, 100
    div   $t2, $t0
    mflo  $t1
    mfhi  $t2
    addiu $t1, $t1, '0'
    sb    $t1, 0($t5)
    addiu $t5, $t5, 1
    addiu $t6, $t6, 1

    li    $t0, 10
    div   $t2, $t0
    mflo  $t1
    mfhi  $t2
    addiu $t1, $t1, '0'
    sb    $t1, 0($t5)
    addiu $t5, $t5, 1
    addiu $t6, $t6, 1

    addiu $t2, $t2, '0'
    sb    $t2, 0($t5)
    addiu $t5, $t5, 1
    addiu $t6, $t6, 1

    sb    $zero, 0($t5)         # null-terminate

    # ---- Leading spaces ----
    beqz  $s4, fw_print
    sub   $t3, $s4, $t6
    blez  $t3, fw_print

fw_spaces:
    beqz  $t3, fw_print
    la    $a0, STR_SPACE
    li    $v0, 4
    syscall
    lw    $a0, out_fd
    la    $a1, STR_SPACE
    li    $a2, 1
    li    $v0, 15
    syscall
    addiu $t3, $t3, -1
    j     fw_spaces

fw_print:
    la    $a0, num_buf
    li    $v0, 4
    syscall

    lw    $a0, out_fd
    la    $a1, num_buf
    move  $a2, $t6
    li    $v0, 15
    syscall

    lw    $ra,  0($sp)
    lw    $s0,  4($sp)
    lw    $s1,  8($sp)
    lw    $s2, 12($sp)
    lw    $s3, 16($sp)
    lw    $s4, 20($sp)
    lw    $s5, 24($sp)
    addiu $sp, $sp, 28
    jr    $ra
