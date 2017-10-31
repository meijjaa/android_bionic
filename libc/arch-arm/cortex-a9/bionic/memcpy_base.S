/*
 * Copyright (C) 2008 The Android Open Source Project
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in
 *    the documentation and/or other materials provided with the
 *    distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
 * OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
 * AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
 * OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

/*
 * This code assumes it is running on a processor that supports all arm v7
 * instructions, that supports neon instructions, and that has a 32 byte
 * cache line.
 */

ENTRY_PRIVATE(MEMCPY_BASE)
        .cfi_def_cfa_offset 8
        .cfi_rel_offset r0, 0
        .cfi_rel_offset lr, 4

        // Check so divider is at least 16 bytes, needed for alignment code.
        cmp         r2, #0
        ble         out
        pld         [r1]
        cmp         r2, #64
        blt         .Lmemcpy_quick
        eor         r3, r1, r0
        tst         r3, #0x03               // temp data
        bne         use_neon                // src and dest cannot make align
        tst         r1, #0x03
        beq         aligned_cpy

make_align:
        ldrb        r3, [r1], #1
        subs        r2,  r2,  #1
        strb        r3, [r0], #1
        beq         out
        tst         r1, #0x03
        bne         make_align

aligned_cpy:
        cmp         r2, #68
        blt         less_64_nocheck
        tst         r1, #0x04
        beq         aligned_64
        ldr         r3, [r1], #4
        subs        r2, #4
        str         r3, [r0], #4               // align to 8 bytes
        beq         out
aligned_64:
        subs        r2, #64
        pld         [r1, #32]
        blt         less_64
        pld         [r1, #64]
        pld         [r1, #96]
        .align  3
loop_main:
        vldmia      r1!, {q0 - q3}              // 8
        pld         [r1, #128]                  // 1
        pld         [r1, #160]                  // 1
        subs        r2,  #64                    // 1
        vstmia      r0!, {q0 - q3}              // 8
        bge         loop_main                   // 1  64 / 20 = 3.2 bytes/cycle

less_64:
        adds        r2,  #64
        beq         out
less_64_nocheck:
        cmp         r2,  #8
        blt         less_8
loop_arm_8:
        vldmia      r1!, {d0}
        sub         r2,  #8
        cmp         r2,  #8
        vstmia      r0!, {d0}
        bge         loop_arm_8
less_8:
        movs        r12, r2, lsl #30
        itt         cs
        ldrcs       r3, [r1], #4
        strcs       r3, [r0], #4
        itt         mi
        ldrhmi      r3, [r1], #2
        strhmi      r3, [r0], #2
        tst         r2,  #1
        itt         ne
        ldrbne      r3, [r1], #1
        strbne      r3, [r0], #1
out:
1:
        pop         {r0, pc}

use_neon:
        cmp         r2, #64
        blt         use_neon_less64
use_neon_loop:
        vld1.8      {q0, q1}, [r1]!
        vld1.8      {q2, q3}, [r1]!
        sub         r2, #64
        pld         [r1, #64]
        pld         [r1, #96]
        cmp         r2, #64
        vst1.8      {q0, q1}, [r0]!
        vst1.8      {q2, q3}, [r0]!
        bge         use_neon_loop
use_neon_less64:
        cmp         r2, #32
        blt         use_neon_less32
        vld1.8      {q0, q1}, [r1]!
        subs        r2, #32
        vst1.8      {q0, q1}, [r0]!
        beq         out
use_neon_less32:
        cmp         r2, #16
        blt         use_neon_less16
        vld1.8      {q0}, [r1]!
        subs        r2, #16
        vst1.8      {q0}, [r0]!
        beq         out
use_neon_less16:
        cmp         r2, #8
        blt         less_8
        vld1.8      {d0}, [r1]!
        subs        r2, #8
        vst1.8      {d0}, [r0]!
        beq         out
        b           less_8
.Lmemcpy_quick:
        mov         lr, #1
.Lmemcpy_quick_loop:
        clz         r12, r2
        rsb         r12, #31
        lsl         r3,  lr, r12
        tbb         [pc, r12]
.Lmemcpy_quick_table:
        //.byte       0
        .byte       ((.Lmemcpy_quick_1  - .Lmemcpy_quick_table)/2)
        .byte       ((.Lmemcpy_quick_2  - .Lmemcpy_quick_table)/2)
        .byte       ((.Lmemcpy_quick_4  - .Lmemcpy_quick_table)/2)
        .byte       ((.Lmemcpy_quick_8  - .Lmemcpy_quick_table)/2)
        .byte       ((.Lmemcpy_quick_16 - .Lmemcpy_quick_table)/2)
        .byte       ((.Lmemcpy_quick_32 - .Lmemcpy_quick_table)/2)
        .p2align 2
.Lmemcpy_quick_1:
        ldrb        r12, [r1], #1
        bic         r2, r3
        strb        r12, [r0], #1
        cbz         r2, .Lout_quick
        b           .Lmemcpy_quick_loop
.Lmemcpy_quick_2:
        ldrh        r12, [r1], #2
        bic         r2, r3
        strh        r12, [r0], #2
        cbz         r2, .Lout_quick
        b           .Lmemcpy_quick_loop
.Lmemcpy_quick_4:
        ldr         r12, [r1], #4
        bic         r2, r3
        str         r12, [r0], #4
        cbz         r2, .Lout_quick
        b           .Lmemcpy_quick_loop
.Lmemcpy_quick_8:
        vld1.8      {d0}, [r1]!
        bic         r2, r3
        vst1.8      {d0}, [r0]!
        cbz         r2, .Lout_quick
        b           .Lmemcpy_quick_loop
.Lmemcpy_quick_16:
        vld1.8      {d0, d1}, [r1]!
        bic         r2, r3
        vst1.8      {d0, d1}, [r0]!
        cbz         r2, .Lout_quick
        b           .Lmemcpy_quick_loop
.Lmemcpy_quick_32:
        vld1.8      {d0, d1, d2, d3}, [r1]!
        bic         r2, r3
        vst1.8      {d0, d1, d2, d3}, [r0]!
        cbz         r2, .Lout_quick
        b           .Lmemcpy_quick_loop
.Lout_quick:
        pop         {r0, pc}


END(MEMCPY_BASE)

ENTRY_PRIVATE(MEMCPY_BASE_ALIGNED)
        .cfi_def_cfa_offset 8
        .cfi_rel_offset r0, 0
        .cfi_rel_offset lr, 4

        /* Simple arm-only copy loop to handle aligned copy operations */
        stmfd       sp!, {r4-r8}
        .cfi_adjust_cfa_offset 20
        .cfi_rel_offset r4, 0
        .cfi_rel_offset r5, 4
        .cfi_rel_offset r6, 8
        .cfi_rel_offset r7, 12
        .cfi_rel_offset r8, 16
        pld         [r1, #(32 * 4)]

        /* Check alignment */
        rsb         r3, r1, #0
        ands        r3, #3
        beq         2f

        /* align source to 32 bits. We need to insert 2 instructions between
         * a ldr[b|h] and str[b|h] because byte and half-word instructions
         * stall 2 cycles.
         */
        movs        r12, r3, lsl #31
        sub         r2, r2, r3      /* we know that r3 <= r2 because r2 >= 4 */
        itt         mi
        ldrbmi      r3, [r1], #1
        strbmi      r3, [r0], #1
        itttt       cs
        ldrbcs      r4, [r1], #1
        ldrbcs      r5, [r1], #1
        strbcs      r4, [r0], #1
        strbcs      r5, [r0], #1

2:
        subs        r2, r2, #64
        blt         4f

3:      /* Main copy loop, copying 64 bytes at a time */
        pld         [r1, #(32 * 8)]
        ldmia       r1!, {r3, r4, r5, r6, r7, r8, r12, lr}
        stmia       r0!, {r3, r4, r5, r6, r7, r8, r12, lr}
        ldmia       r1!, {r3, r4, r5, r6, r7, r8, r12, lr}
        stmia       r0!, {r3, r4, r5, r6, r7, r8, r12, lr}
        subs        r2, r2, #64
        bge         3b

4:      /* Check if there are > 32 bytes left */
        adds        r2, r2, #64
        subs        r2, r2, #32
        blt         5f

        /* Copy 32 bytes */
        ldmia       r1!, {r3, r4, r5, r6, r7, r8, r12, lr}
        stmia       r0!, {r3, r4, r5, r6, r7, r8, r12, lr}
        subs        r2, #32

5:      /* Handle any remaining bytes */
        adds        r2, #32
        beq         6f

        movs        r12, r2, lsl #28
        itt         cs
        ldmiacs     r1!, {r3, r4, r5, r6}   /* 16 bytes */
        stmiacs     r0!, {r3, r4, r5, r6}
        itt         mi
        ldmiami     r1!, {r7, r8}           /*  8 bytes */
        stmiami     r0!, {r7, r8}
        movs        r12, r2, lsl #30
        itt         cs
        ldrcs       r3, [r1], #4            /*  4 bytes */
        strcs       r3, [r0], #4
        itt         mi
        ldrhmi      r4, [r1], #2            /*  2 bytes */
        strhmi      r4, [r0], #2
        tst         r2, #0x1
        itt         ne
        ldrbne      r3, [r1]                /*  last byte  */
        strbne      r3, [r0]
6:
        ldmfd       sp!, {r4-r8}
        ldmfd       sp!, {r0, pc}
END(MEMCPY_BASE_ALIGNED)
