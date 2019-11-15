;========================================;
;#	MAIN.S - T-DOS kernel;		#;
;#	By Timur Salomakhin;		#;
;#	mahin.tim@gmail.com;		#;
;#	See README and LICENSE;		#;
;========================================;


;NASM directives;
[BITS 16]
[CPU 8086]
[ORG $900]
;==== ==== ====


jmp	KERNEL_ENTRY ;Jumping to the kernel's entry point;


;Constants;
FALSE		EQU	0
TRUE		EQU	(!FALSE)
KERNEL		EQU	$900
KERNEL_SIZE	EQU	$4000
SYS_STACK	EQU	KERNEL+KERNEL_SIZE
SYS_STACK_SIZE	EQU	$4000
FREE_MEM	EQU	SYS_STACK+SYS_STACK_SIZE
;==== ==== ====


;Including other source files;
%INCLUDE "KERNEL/ERRORS.S"
%INCLUDE "KERNEL/TASK.S"
;==== ==== ====


;KERNEL_ENTRY - subprogram;
;Kernel's entry point;
;IN:
;	[$900-?] - kernel file;
;	AX - cylinders number;
;	BH - sectors number;
;	BL - heads number;
;	DL - boot device number;
;	BP - version of TFS;
;	SI:DI - number of sectors; 
;NOTE:
;	Infinity loop;
KERNEL_ENTRY:
	cli

	;Loading TFS and disk's data into variables;
	mov	[CYLINDERS], ax
	mov	[SECTORS], bh
	mov	[HEADS], bl
	mov	[DRIVE_NUM], dl
	mov	[TFS_VERSION], bp
	mov	[TFS_SECTORS], di
	mov	[TFS_SECTORS+2], si
	;====

	;Setting segments registers and stack;
	xor	ax, ax
	mov	ds, ax
	mov	es, ax
	mov	ax, SYS_STACK
	mov	ss, ax
	;====

	;Setting 20th interrupt handler in IVT;
	mov	word [$20*4], AUX_TASK_LEAVE
	mov	word [$20*4+2], 0
	;====

.INIT_SEGS:
	;Cleaning segment tab;
	mov	ax, 0
	mov	cx, SEGS_NUM/2
	mov	di, SEG_TAB
	rep	stosb
	;====

	;Calculating index of segment in tab that is going after the last
	;segment;
	sti
	int	$12
	cli
	sub	ax, KERNEL/1024
	mov	bx, SEG_SIZE/1024
	div	bl
	cmp	al, SEGS_NUM
	jg	.INIT_TASKS
	;====

	;Setting invalid status to segment that is next to the last segment;
	mov	bl, al
	mov	byte [SEG_TAB+1+bx], $0FF
	;====

.INIT_TASKS:
	;Saving old int8 handler;
	mov	ax, [8*4]
	mov	[INT8_OLD_OFFS], ax
	mov	ax, [8*4+2]
	mov	[INT8_OLD_SEG], ax
	;====

	;Setting new int8 handler;
	mov	word [8*4], INT8_HAND
	mov	word [8*4+2], 0
	;====

	;Filling task tab with 0;
	mov	cx, TASK_TAB_SIZE/2
	mov	di, TASK_TAB
	mov	ax, 0
	rep	stosb
	;====

.END:
	hlt
;==== ==== ====


;INT_HAND - interrupt handler;
;Main T-DOS interrupt handler;
;IN:
;	AH - function's code
;OUT:
;	CF - error flag;
;	AH - error code (if CF == 1)
;
INT_HAND:
;==== ==== ====


;Variable data;
TMP:
	DW	0
TMP2:
	DW	0
TMP3:
	DW	0
;====