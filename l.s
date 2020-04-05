#include "mem.h"

MODE $32

#define DELAY		BYTE $0xEB; BYTE $0x00	/* JMP .+2 */

#define pFARJMP32(s, o)	BYTE $0xea;		/* far jump to ptr32:16 */\
			LONG $o; WORD $s

/*
 * Enter here in 32-bit protected mode. Welcome to 1982.
 * Make sure the GDT is set as it should be:
 *	disable interrupts;
 *	load the GDT with the table in _gdt32p;
 *	load all the data segments
 *	load the code segment via a far jump.
 */
TEXT _protected<>(SB), 1, $-4
	CLI

	MOVL	$_gdtptr32p<>-KZERO(SB), AX
	MOVL	(AX), GDTR

	MOVL	$SELECTOR(2, SELGDT, 0), AX
	MOVW	AX, DS
	MOVW	AX, ES
	MOVW	AX, FS
	MOVW	AX, GS
	MOVW	AX, SS

	pFARJMP32(SELECTOR(3, SELGDT, 0), _warp64<>-KZERO(SB))

	BYTE	$0x90	/* align */

/*
 * Must be 4-byte aligned.
 */
TEXT _multibootheader<>(SB), 1, $-4
	LONG	$0x1BADB002			/* magic */
	LONG	$0x00010007			/* flags */
	LONG	$-(0x1BADB002 + 0x00010007)	/* checksum */
	LONG	$_multibootheader<>-KZERO(SB)	/* header_addr */
	LONG	$_protected<>-KZERO(SB)		/* load_addr */
	LONG	$edata-KZERO(SB)		/* load_end_addr */
	LONG	$end-KZERO(SB)			/* bss_end_addr */
	LONG	$_multibootentry<>-KZERO(SB)	/* entry_addr */
	LONG	$0				/* mode_type */
	LONG	$0				/* width */
	LONG	$0				/* height */
	LONG	$32				/* depth */

/* 
 * the kernel expects the data segment to be page-aligned
 * multiboot bootloaders put the data segment right behind text
 */
TEXT _multibootentry<>(SB), 1, $-4
	MOVL	$etext-KZERO(SB), SI
	MOVL	SI, DI
	ADDL	$(BY2PG-1), DI
	ANDL	$~(BY2PG-1), DI
	MOVL	$edata-KZERO(SB), CX
	SUBL	DI, CX
	ADDL	CX, SI
	ADDL	CX, DI
	INCL	CX	/* one more for post decrement */
	STD
	REP; MOVSB
	MOVL	BX, multibootptr-KZERO(SB)
	MOVL	$_protected<>-KZERO(SB), AX
	JMP*	AX

/* multiboot structure pointer (physical address) */
TEXT multibootptr(SB), 1, $-4
	LONG	$0

TEXT _gdt<>(SB), 1, $-4
	/* null descriptor */
	LONG	$0
	LONG	$0

	/* (KESEG) 64 bit long mode exec segment */
	LONG	$(0xFFFF)
	LONG	$(SEGL|SEGG|SEGP|(0xF<<16)|SEGPL(0)|SEGEXEC|SEGR)

	/* 32 bit data segment descriptor for 4 gigabytes (PL 0) */
	LONG	$(0xFFFF)
	LONG	$(SEGG|SEGB|(0xF<<16)|SEGP|SEGPL(0)|SEGDATA|SEGW)

	/* 32 bit exec segment descriptor for 4 gigabytes (PL 0) */
	LONG	$(0xFFFF)
	LONG	$(SEGG|SEGD|(0xF<<16)|SEGP|SEGPL(0)|SEGEXEC|SEGR)


TEXT _gdtptr32p<>(SB), 1, $-4
	WORD	$(4*8-1)
	LONG	$_gdt<>-KZERO(SB)

TEXT _gdtptr64p<>(SB), 1, $-4
	WORD	$(4*8-1)
	QUAD	$_gdt<>-KZERO(SB)

TEXT _gdtptr64v<>(SB), 1, $-4
	WORD	$(4*8-1)
	QUAD	$_gdt<>(SB)

/*
 * Macros for accessing page table entries; change the
 * C-style array-index macros into a page table byte offset
 */
#define PML4O(v)	((PTLX((v), 3))<<3)
#define PDPO(v)		((PTLX((v), 2))<<3)
#define PDO(v)		((PTLX((v), 1))<<3)
#define PTO(v)		((PTLX((v), 0))<<3)

TEXT _warp64<>(SB), 1, $-4

	/* clear mach and page tables */
	MOVL	$((CPU0END-CPU0PML4)>>2), CX
	MOVL	$(CPU0PML4-KZERO), SI
	MOVL	SI, DI
	XORL	AX, AX
	CLD
	REP;	STOSL

	MOVL	SI, AX				/* PML4 */
	MOVL	AX, DX
	ADDL	$(PTSZ|PTEWRITE|PTEVALID), DX	/* PDP at PML4 + PTSZ */
	MOVL	DX, PML4O(0)(AX)		/* PML4E for double-map */
	MOVL	DX, PML4O(KZERO)(AX)		/* PML4E for KZERO */

	ADDL	$PTSZ, AX			/* PDP at PML4 + PTSZ */
	ADDL	$PTSZ, DX			/* PD0 at PML4 + 2*PTSZ */
	MOVL	DX, PDPO(0)(AX)			/* PDPE for double-map */
	MOVL	DX, PDPO(KZERO)(AX)		/* PDPE for KZERO */

	/*
	 * add PDPE for KZERO+1GB early as Vmware
	 * hangs when modifying kernel PDP
	 */
	ADDL	$PTSZ, DX			/* PD1 */
	MOVL	DX, PDPO(KZERO+GiB)(AX)

	ADDL	$PTSZ, AX			/* PD0 at PML4 + 2*PTSZ */
	MOVL	$(PTESIZE|PTEGLOBAL|PTEWRITE|PTEVALID), DX
	MOVL	DX, PDO(0)(AX)			/* PDE for double-map */

	/*
	 * map from KZERO to end using 2MB pages
	 */
	ADDL	$PDO(KZERO), AX
	MOVL	$end-KZERO(SB), CX

	ADDL	$(16*1024), CX			/* qemu puts multiboot data after the kernel */

	ADDL	$(PGLSZ(1)-1), CX
	ANDL	$~(PGLSZ(1)-1), CX
	MOVL	CX, MemMin-KZERO(SB)		/* see memory.c */
	SHRL	$(1*PTSHIFT+PGSHIFT), CX
memloop:
	MOVL	DX, (AX)
	ADDL	$PGLSZ(1), DX
	ADDL	$8, AX
	LOOP	memloop

/*
 * Enable and activate Long Mode. From the manual:
 * 	make sure Page Size Extentions are off, and Page Global
 *	Extensions and Physical Address Extensions are on in CR4;
 *	set Long Mode Enable in the Extended Feature Enable MSR;
 *	set Paging Enable in CR0;
 *	make an inter-segment jump to the Long Mode code.
 * It's all in 32-bit mode until the jump is made.
 */
TEXT _lme<>(SB), 1, $-4
	MOVL	SI, CR3				/* load the mmu */
	DELAY

	MOVL	CR4, AX
	ANDL	$~0x00000010, AX			/* Page Size */
	ORL	$0x000000A0, AX			/* Page Global, Phys. Address */
	MOVL	AX, CR4

	MOVL	$0xc0000080, CX			/* Extended Feature Enable */
	RDMSR
	ORL	$0x00000100, AX			/* Long Mode Enable */
	WRMSR

	MOVL	CR0, DX
	ANDL	$~0x6000000a, DX
	ORL	$0x80010000, DX			/* Paging Enable, Write Protect */
	MOVL	DX, CR0

	pFARJMP32(SELECTOR(KESEG, SELGDT, 0), _identity<>-KZERO(SB))

/*
 * Long mode. Welcome to 2003.
 * Jump out of the identity map space;
 * load a proper long mode GDT.
 */
MODE $64

TEXT _identity<>(SB), 1, $-4
	MOVQ	$_start64v<>(SB), AX
	JMP*	AX

TEXT _start64v<>(SB), 1, $-4
	MOVQ	$_gdtptr64v<>(SB), AX
	MOVL	(AX), GDTR

	XORQ	AX, AX
	MOVW	AX, DS				/* not used in long mode */
	MOVW	AX, ES				/* not used in long mode */
	MOVW	AX, FS
	MOVW	AX, GS
	MOVW	AX, SS				/* not used in long mode */

	MOVW	AX, LDTR

	MOVQ	$(CPU0MACH+MACHSIZE), SP
	MOVQ	$(CPU0MACH), RMACH
	MOVQ	AX, RUSER			/* up = 0; */

_clearbss:
	MOVQ	$edata(SB), DI
	MOVQ	$end(SB), CX
	SUBQ	DI, CX				/* end-edata bytes */
	SHRQ	$2, CX				/* end-edata doublewords */

	CLD
	REP;	STOSL				/* clear BSS */

	PUSHQ	AX				/* clear flags */
	POPFQ

	CALL	main(SB)

/*
 * Park a processor. Should never fall through a return from main to here,
 * should only be called by application processors when shutting down.
 */
TEXT idle(SB), 1, $-4
_idle:
	STI
	HLT
	JMP	_idle

/*
 * The CPUID instruction is always supported on the amd64.
 */
TEXT cpuid(SB), $-4
	MOVL	RARG, AX			/* function in AX */
	CPUID

	MOVQ	info+8(FP), BP
	MOVL	AX, 0(BP)
	MOVL	BX, 4(BP)
	MOVL	CX, 8(BP)
	MOVL	DX, 12(BP)
	RET

/*
 * Port I/O.
 */
TEXT inb(SB), 1, $-4
	MOVL	RARG, DX			/* MOVL	port+0(FP), DX */
	XORL	AX, AX
	INB
	RET

TEXT insb(SB), 1, $-4
	MOVL	RARG, DX			/* MOVL	port+0(FP), DX */
	MOVQ	address+8(FP), DI
	MOVL	count+16(FP), CX
	CLD
	REP;	INSB
	RET

TEXT ins(SB), 1, $-4
	MOVL	RARG, DX			/* MOVL	port+0(FP), DX */
	XORL	AX, AX
	INW
	RET

TEXT inss(SB), 1, $-4
	MOVL	RARG, DX			/* MOVL	port+0(FP), DX */
	MOVQ	address+8(FP), DI
	MOVL	count+16(FP), CX
	CLD
	REP;	INSW
	RET

TEXT inl(SB), 1, $-4
	MOVL	RARG, DX			/* MOVL	port+0(FP), DX */
	INL
	RET

TEXT insl(SB), 1, $-4
	MOVL	RARG, DX			/* MOVL	port+0(FP), DX */
	MOVQ	address+8(FP), DI
	MOVL	count+16(FP), CX
	CLD
	REP; INSL
	RET

TEXT outb(SB), 1, $-1
	MOVL	RARG, DX			/* MOVL	port+0(FP), DX */
	MOVL	byte+8(FP), AX
	OUTB
	RET

TEXT outsb(SB), 1, $-4
	MOVL	RARG, DX			/* MOVL	port+0(FP), DX */
	MOVQ	address+8(FP), SI
	MOVL	count+16(FP), CX
	CLD
	REP; OUTSB
	RET

TEXT outs(SB), 1, $-4
	MOVL	RARG, DX			/* MOVL	port+0(FP), DX */
	MOVL	short+8(FP), AX
	OUTW
	RET

TEXT outss(SB), 1, $-4
	MOVL	RARG, DX			/* MOVL	port+0(FP), DX */
	MOVQ	address+8(FP), SI
	MOVL	count+16(FP), CX
	CLD
	REP; OUTSW
	RET

TEXT outl(SB), 1, $-4
	MOVL	RARG, DX			/* MOVL	port+0(FP), DX */
	MOVL	long+8(FP), AX
	OUTL
	RET

TEXT outsl(SB), 1, $-4
	MOVL	RARG, DX			/* MOVL	port+0(FP), DX */
	MOVQ	address+8(FP), SI
	MOVL	count+16(FP), CX
	CLD
	REP; OUTSL
	RET

TEXT getgdt(SB), 1, $-4
	MOVQ	RARG, AX
	MOVL	GDTR, (AX)			/* Note: 10 bytes returned */
	RET

TEXT lgdt(SB), $0				/* GDTR - global descriptor table */
	MOVQ	RARG, AX
	MOVL	(AX), GDTR
	RET

TEXT lidt(SB), $0				/* IDTR - interrupt descriptor table */
	MOVQ	RARG, AX
	MOVL	(AX), IDTR
	RET

TEXT ltr(SB), 1, $-4
	MOVW	RARG, AX
	MOVW	AX, TASK
	RET
