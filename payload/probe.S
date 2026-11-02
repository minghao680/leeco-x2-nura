/*
 * lk2nd handoff probe ("black box recorder") for LeEco Le Max 2 (x2).
 *
 * Problem: the mainline kernel dies within ~3-5s when booted via lk2nd,
 * before ramoops/pstore init, so we can never see what lk2nd actually
 * handed to it (memory map, cmdline, patched DTB).
 *
 * This tiny bare-metal arm64 payload is booted by lk2nd EXACTLY like a
 * real kernel (same decompress/DTB-select/patch/jump path). At entry the
 * boot protocol gives us x0 = physical address of the DTB that lk2nd
 * prepared. We dump into the stock 3.18 kernel's pstore console-ramoops
 * buffer (which survives a warm reset):
 *     data[0..7]   "LKPROBE1"
 *     data[8..15]  x0 (DTB pointer)
 *     data[16..23] CurrentEL
 *     data[24..31] SCTLR_EL1
 *     data[32..]   first 8 KiB at [x0]
 *     data[8224]   w0 returned by SMC (only reached if reset failed)
 *     data[8228..] 256 bytes at the first "console=" found in the DTB
 *                  (= the final bootargs lk2nd wrote into /chosen)
 * then resets via PSCI. Back on Android:
 *     /sys/fs/pstore/console-ramoops
 * contains our record, parseable offline.
 *
 * Layout requirements (verified against the vendor 3.18 sources in
 * android_kernel_leeco_msm8996/fs/pstore/{ram.c,ram_core.c}):
 *   - ramoops region 0x91500000..0x91600000, allocation order:
 *       dmesg record przs : 0x91500000, 10 x 0x10000 = 0xA0000
 *       console      prz  : 0x915A0000, 0x40000
 *       ftrace            : 0 size
 *       pmsg         prz  : 0x915E0000, 0x20000
 *   - struct persistent_ram_buffer { u32 sig; u32 start; u32 size; u8 data[]; }
 *   - console zone sig param is 0, stored sig = 0 ^ 0x43474244 = 0x43474244
 *   - ecc = 0 (module param), so data starts right after the 12-byte header
 *
 * Image header: lk2nd's IS_ARM64() requires the "ARM\x64" magic at offset
 * 0x38, and it applies  (kernel_addr & ~0x1fffff) + text_offset  before
 * loading, so we present a minimal arm64 Image header with text_offset 0.
 * Entry is at image start (the branch below).
 */

.text
.globl _start
_start:
	b	code

	/* --- minimal arm64 Image header (64 bytes) --- */
	.balign	8
	.quad	0			/* 0x08 text_offset */
	.quad	0x100000		/* 0x10 image_size (nonzero) */
	.quad	0			/* 0x18 flags */
	.quad	0			/* 0x20 */
	.quad	0			/* 0x28 res2 */
	.quad	0			/* 0x30 res3 */
	.ascii	"ARM\x64"		/* 0x38 magic */
	.balign	8

code:
	/* x0 = DTB pointer from lk2nd */
	mov	x19, x0

	/* console buffer @ 0x915A0000 */
	movz	x20, #0x915A, lsl #16

	/* sig = 0x43474244, start = 0, size = 16676 */
	mov	w21, #0x4244
	movk	w21, #0x4347, lsl #16
	str	w21, [x20]
	str	wzr, [x20, #4]
	movz	w21, #16676
	str	w21, [x20, #8]

	/* data[0..7] = "LKPROBE1" */
	movz	x21, #0x4B4C		/* "LK"   */
	movk	x21, #0x5250, lsl #16	/* "PR"   */
	movk	x21, #0x454F, lsl #32	/* "OE"   */
	movk	x21, #0x3131, lsl #48	/* "11"   */
	str	x21, [x20, #12]

	/* data[8..15] = x0 (DTB pointer) */
	str	x19, [x20, #20]

	/* data[16..23] = CurrentEL (diag: where did lk2nd drop us?) */
	mrs	x21, CurrentEL
	str	x21, [x20, #28]

	/* data[24..31] = SCTLR_EL1 (diag: MMU/cache state at entry) */
	mrs	x21, sctlr_el1
	str	x21, [x20, #36]

	/* data[32..16415] = first 16384 bytes at [x0] */
	add	x22, x20, #44
	mov	x23, #16384
1:	ldr	x24, [x19], #8
	str	x24, [x22], #8
	subs	x23, x23, #8
	b.ne	1b

	/* search the 8-byte needle "console=" within the whole DTB (64 KiB) */
	sub	x19, x19, #16384
	movz	x24, #0x6F63		/* "co" */
	movk	x24, #0x6E73, lsl #16	/* "ns" */
	movk	x24, #0x6C6F, lsl #32	/* "ol" */
	movk	x24, #0x3D65, lsl #48	/* "e=" */
	movz	x25, #0x4000
	movk	x25, #0x0001, lsl #16	/* 0x10000 = 64 KiB */
	movz	x26, #0x4050		/* 16432: cmdline slot offset */
	add	x26, x20, x26
2:	ldr	x27, [x19], #8
	cmp	x27, x24
	b.eq	3f
	subs	x25, x25, #8
	b.ne	2b
	/* not found: park a marker */
	movz	x27, #0x4F4E		/* "NO" */
	movk	x27, #0x4F43, lsl #16	/* "CO" */
	movk	x27, #0x4E53, lsl #32	/* "SN" */
	movk	x27, #0x4C4F, lsl #48	/* "OL" */
	str	x27, [x26]
	b	4f
3:	/* found at x19-8: copy 256 bytes from there */
	sub	x27, x19, #8
	mov	x25, #256
31:	ldr	x28, [x27], #8
	str	x28, [x26], #8
	subs	x25, x25, #8
	b.ne	31b

4:	/* clean dcache over everything we wrote, then barrier */
	movz	x25, #0x8000
	add	x27, x20, #0
5:	dc	cvac, x27
	add	x27, x27, #64
	subs	x25, x25, #64
	b.gt	5b
	dsb	sy
	isb

	/*
	 * Arm the KPSS watchdog @0x9830000 (bite in ~5s @32768Hz) BEFORE
	 * trying PSCI: whatever goes wrong from here on (smc hangs, reset
	 * unsupported) still ends in a hardware reset, so the probe never
	 * needs a manual force-reboot. WDT_RST=0x0, WDT_EN=0x8,
	 * WDT_BITE_TIME=0x24 (vendor drivers/watchdog/qcom-wdt.c).
	 */
	movz	x25, #0x9830, lsl #16	/* 0x98300000 */
	movz	x27, #0x8000
	movk	x27, #0x0002, lsl #16	/* 0x28000 = 5s */
	str	x27, [x25, #0x24]	/* bite time */
	mov	w27, #1
	str	w27, [x25]		/* rst */
	str	w27, [x25, #8]		/* enable */
	dsb	sy

	/* PSCI SYSTEM_RESET (0x84000009): SMC first, HVC fallback, else spin */
	mov	w0, #0x0009
	movk	w0, #0x8400, lsl #16
	smc	#0

	/* still here: reset failed. record SMC's return code for post-mortem */
	movz	x28, #0x402C		/* 16428: smc-ret slot offset */
	add	x28, x20, x28
	str	w0, [x28]
	mov	x25, #512
	movz	x27, #0x4000
	add	x27, x20, x27
6:	dc	cvac, x27
	add	x27, x27, #64
	subs	x25, x25, #64
	b.gt	6b
	dsb	sy

	mov	w0, #0x0009
	movk	w0, #0x8400, lsl #16
	hvc	#0

7:	wfi
	b	7b