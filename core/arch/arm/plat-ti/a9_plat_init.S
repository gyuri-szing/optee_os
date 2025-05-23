/* SPDX-License-Identifier: BSD-2-Clause */
/*
 * Copyright (C) 2017 Texas Instruments Incorporated - http://www.ti.com/
 *	Andrew Davis <afd@ti.com>
 */

/*
 * Entry points for the A9 init.
 * It is assumed no stack is available when these routines are called.
 * It is assumed each routine is called with return address in LR
 * and with ARM registers R0, R1, R2, R3 being scratchable.
 */

#include <asm.S>
#include <generated/asm-defines.h>
#include <platform_config.h>
#include <sm/optee_smc.h>
#include <sm/teesmc_opteed.h>
#include <sm/teesmc_opteed_macros.h>

.arch_extension sec

.section .text
.balign 4
.code 32

booted:
	.word	0

/*
 * Cortex A9 check for resume
 *
 * Use scratables registers R0-R3.
 * No stack usage.
 * LR store return address.
 * Trap CPU in case of error.
 */
FUNC plat_cpu_reset_early , :
	/* Check if we are resuming */
	ldr	r3, =booted
	ldr	r2, [r3]
	cmp	r2, #0
	/* Cold boot, mark our boot flag and return to normal boot */
	moveq	r2, #1
	streq	r2, [r3]
	bxeq	lr
	/* Otherwise we are resuming */
	b	resume_springboard
END_FUNC plat_cpu_reset_early

LOCAL_FUNC resume_springboard , :
UNWIND(	.cantunwind)
	/* Setup tmp stack */
	bl	__get_core_pos
	cmp	r0, #CFG_TEE_CORE_NB_CORE
	/* Unsupported CPU, park it before it breaks something */
unhandled_cpu:
	wfige
	bge	unhandled_cpu

	ldr	r1, =thread_core_local
	ldr	r1, [r1]
	mov	r2, #THREAD_CORE_LOCAL_SIZE
	/* r3 = r2 * r0 + r1 */
	mla	r3, r2, r0, r1
	ldr	sp, [r3, #THREAD_CORE_LOCAL_TMP_STACK_VA_END]

	/* Push our return on the stack as sm_pm_cpu_do_resume expects */
	adr	lr, after_resume
	push	{r4 - r12, lr}

	/* Assumes suspend_regs is flat-mapped */
	ldr	r0, =suspend_regs
	bl	sm_pm_cpu_do_resume

after_resume:
	bl	thread_init_per_cpu

	/* r5 contains the non-secure entry address (ARMv7 bootarg #0) */
	mov	r0, r5
	bl	init_sec_mon

	bl	boot_primary_init_intc

	mov	r0, #TEESMC_OPTEED_RETURN_ENTRY_DONE
	mov	r1, #0
	mov	r2, #0
	mov	r3, #0
	mov	r4, #0
	smc	#0
	b	.	/* SMC should not return */
END_FUNC resume_springboard
