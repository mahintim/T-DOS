;========================================;
;#	MAIN.S - Task service;		#;
;#	By Timur Salomakhin;		#;
;#	mahin.tim@gmail.com;		#;
;#	See README and LICENSE;		#;
;========================================;


;==== Segmentation explanation ====
;	Read 8086/8088 datasheet to get more info about segmentation;
;	Memory is splitted into user-mode memory and system-memory (see table
;	1.0).  Each user-memory segment in T-DOS has fixed size 16 KiB and can
;	be occupied by any task.
;
;	Segment tab - is an array at $800 and it contains statuses of all
;	available segments for user mode programs, each element contains ID of
;	the task that occupied that segment;
;	If element in tab is $00 then it's free, or $0FF if it's invalid
;	segment (or one that follows the last segment), or $0FE if it's
;	occupied by kernel or by other system's services; 
;
;
;	(table 1)
;	SYSTEM MEMORY
;	+------------+ $00000
;	| IVT        | Interrupt Vector Table;
;	+------------+ $00400
;	| BIOS_DATA  | BIOS data area;
;	+------------+ $00502
;	| NIU        | Not in use;
;	+------------+ $00600
;	| IO_BUF     | Buffer for IO;
;	+------------+ $00800
;	| KERN_DATA  | Kernel's data area;
;	+------------+ $00900
;	| KERN_CODE  | Kernel's code area;
;	+------------+ $04900
;	| KERN_STACK | Kernel's stack area;
;	+------------+ $08900
;	USER MEMORY
;	+------------+ $08900
;	| SEGS       | 38 16 KiB segments;
;	+------------+ $A0000
;
;
;==== Multitasking explanation ====
;	T-DOS is using cooperative multitasking.  All tasks' scheduler's data
;	is saved in array at $800+SEGS_NUM.  There is one main task and up to
;	sixteen auxiliary tasks that are working in background mode.  When main
;	task is terminating, auxiliary tasks aren't terminating and control
;	returns to the command prompt.  Every 220ms one of auxiliary tasks is
;	called.  Multitasking can be disabled;


;Constants;
SEG_TAB		EQU	$800
SEG_SIZE	EQU	$4000
SEGS_NUM	EQU	38
TASK_TAB	EQU	(SEG_TAB+SEGS_NUM)
TASK_SIZE	EQU	2
TASKS_NUM	EQU	16
TASK_TAB_SIZE	EQU	(TASK_SIZE*TASKS_NUM)
MAIN_TASK	EQU	(TASK_TAB+TASK_TAB_SIZE)
MAIN_TASK_AX	EQU	MAIN_TASK+0
MAIN_TASK_BX	EQU	MAIN_TASK+2
MAIN_TASK_CX	EQU	MAIN_TASK+4
MAIN_TASK_DX	EQU	MAIN_TASK+6
MAIN_TASK_SI	EQU	MAIN_TASK+8
MAIN_TASK_DI	EQU	MAIN_TASK+10
MAIN_TASK_BP	EQU	MAIN_TASK+12
MAIN_TASK_CS	EQU	MAIN_TASK+14
MAIN_TASK_DS	EQU	MAIN_TASK+16
MAIN_TASK_ES	EQU	MAIN_TASK+18
MAIN_TASK_IP	EQU	MAIN_TASK+20
MAIN_TASK_SIZE	EQU	MAIN_TASK+22
;==== ==== ====


;ALLOC_SEG - subprogram;
;Allocate 16KiB segment in user-memory;
;IN:
;	AL - ID of task;
;OUT:
;	CF - error flag;
;	AH - error code (if CF == 1);
;	AX - first allocated segment (if CF == 0);
SEG_ALLOC:
	mov	si, SEG_TAB
	mov	cx, SEGS_NUM
	mov	bl, al

.FIND_LP:
	cs lodsb
	
	;One free segment found;
	cmp	al, 0
	je	.END
	;====

	;One invalid segment found (no free segments found);
	cmp	al, $0FF
	je	.ERR
	;====
	
	loop	.FIND_LP

.ERR:
	stc
	mov	ah, NO_SEGS_ERR
	ret

.END:
	mov	[cs:si-1], bl

	;Calculating address of segment from index in segment tab;
	mov	ax, si
	sub	ax, SEG_TAB+1
	mov	bx, SEG_SIZE/16
	mul	bx
	add	ax, FREE_MEM/16
	;====

	clc
	ret
;==== ==== ====



;Free 16KiB segment in user-memory;
;IN:
;	AX - segment;
;OUT:
;	CF - error flag;
;	AH - error code (if CF == 1);
SEG_FREE:
	xor	dx, dx

	;Calculating address of segment in segment tab;
	sub	ax, FREE_MEM/16
	mov	bx, TASK_SIZE
	div	bx
	;====

	;Checking that segment is valid;
	cmp	ax, SEGS_NUM
	jge	.ERR
	;====

	;Setting segment's value in segment tab to 0 (freeing segment);
	mov	si, ax
	mov	byte [cs:SEG_TAB+si], 0
	;====

	clc
	ret
	
.ERR:
	stc
	mov	ah, SEG_INV_ERR
	ret
;==== ==== ====


;MULT_OFF - subprogram;
;Disable multitasking;
MULT_OFF:
	mov	ax, [cs:INT8_OLD_OFFS]
	mov	[cs:8*4], ax
	mov	ax, [cs:INT8_OLD_SEG]
	mov	[cs:8*4+2], ax
	sti

	ret
;==== ==== ====


;MULT_ON - subptogram;
;Enable multitasking;
MULT_ON:
	mov	word [cs:8*4], INT8_HAND
	mov	word [cs:8*4+2], 0
	sti

	ret
;==== ==== ====


;INT8_HAND - int handler;
;int8 handler;
INT8_HAND:
	push	ax

	;Calling old int8 handler;
	mov	ax, [cs:INT8_OLD_OFFS]
	mov	word [cs:.CALL_OLD+1], ax
	mov	ax, [cs:INT8_OLD_SEG]
	mov	word [cs:.CALL_OLD+3], ax
	;====

	;Pushing flags (as int instruction);
	pushf
	;====

.CALL_OLD:
	call	0:0

	;Checking that int counter is 0, else leaving the interrupt;
	cmp	byte [cs:INT8_COUNT], 0
	jne	.LEAVE
	;====

	pop	ax

	;Setting int8 counter to 3;
	mov	byte [cs:INT8_COUNT], 3
	;====

	;Saving registers to stack;
	push	si
	push	ax
	push	bx
	;====

	mov	si, [cs:TASK_ID_MULTED]

;Searching for non-free task structs;
.FIND_LP:
	;Checking for end of loop;
	cmp	si, TASKS_NUM*2
	je	.NOT_FOUND
	;====

	;Checking current task's status and call it if its status isn't zero;
	cmp	word [cs:TASK_TAB+si], 0
	jne	.PREP
	;====

	;Increasing task's ID and if ID is equals to number of tasks, then
	;leaving the loop;
	add	si, 2
	;====

	jmp	.FIND_LP

.NOT_FOUND:
	mov	byte [cs:TASK_ID_MULTED], 0

	;Loading registers from stack;
	pop	bx
	pop	ax
	pop	si
	;====

	push	ax
	jmp	.END

.PREP:
	;Preparing before calling auxilary task;

	;Storing ID of the next task;
	push	si
	add	si, 2
	mov	[cs:TASK_ID_MULTED], si
	pop	si
	;====

	pop	bx
	pop	ax

	;Storing main task's register; AX = address of task's struct;
	mov	[cs:MAIN_TASK_AX], ax
	mov	[cs:MAIN_TASK_BX], bx
	mov	[cs:MAIN_TASK_CX], cx
	mov	[cs:MAIN_TASK_DX], dx
	mov	ax, si
	pop	si
	mov	[cs:MAIN_TASK_SI], si
	mov	[cs:MAIN_TASK_DI], di
	mov	[cs:MAIN_TASK_BP], bp
	mov	bp, sp
	mov	bx, [ss:bp+2]
	mov	[cs:MAIN_TASK_CS], bx
	mov	bx, [ss:bp]
	mov	[cs:MAIN_TASK_IP], bx
	mov	[cs:MAIN_TASK_DS], ds
	mov	[cs:MAIN_TASK_ES], es
	;====

	;Setting the stack;
	add	sp, 6
	;====

	;Getting the code segment of the task;
	mov	si, ax
	mov	ax, [cs:TASK_TAB+si]
	mov	[cs:.CALL_TASK+3], ax
	;====

	;Setting data segment of task;
	mov	ds, ax
	;====

	;Sending `magic` signal (end of int8) to 8529;
	mov	al, $20
	out	$20, al
	;====

	;Disabling multitasking and enabling interrupts;
	call	MULT_OFF
	sti
	;====

.CALL_TASK:
	jmp	0:3

.LEAVE:
	dec	byte [cs:INT8_COUNT]

.END:

	;Sending `magic` signal (end of int8) to 8529;
	mov	al, $20
	out	$20, al
	;====

	pop	ax
	iret
;==== ==== ====


;AUX_TASK_LEAVE - int handler;
;Leave an auxilary task;
AUX_TASK_LEAVE:
	;Enable multitasking;
	call	MULT_ON
	;====

	;Loading the main task register's value;
	mov	ax, [cs:MAIN_TASK_IP]
	mov	[.CONT_MAIN_TASK+1], ax
	mov	ax, [cs:MAIN_TASK_CS]
	mov	[.CONT_MAIN_TASK+3], ax
	mov	ax, [cs:MAIN_TASK_ES]
	mov	es, ax
	mov	ax, [cs:MAIN_TASK_DS]
	mov	ds, ax
	mov	ax, [cs:MAIN_TASK_AX]
	mov	bx, [cs:MAIN_TASK_BX]
	mov	cx, [cs:MAIN_TASK_CX]
	mov	dx, [cs:MAIN_TASK_DX]
	mov	si, [cs:MAIN_TASK_SI]
	mov	si, [cs:MAIN_TASK_DI]
	mov	bp, [cs:MAIN_TASK_BP]
	;====

	add	sp, 6

	sti

.CONT_MAIN_TASK:
	jmp	0:0
;==== ==== ====


;Variable data;
;Int8 counter is used for skipping 3 int8 calls to run scheduler only once in
;220ms;
INT8_COUNT:
	DB	3
;Offset of old int8 handler;
INT8_OLD_OFFS:
	DW	0
;Segment of old int8 handler;
INT8_OLD_SEG:
	DW	0
;ID of current task multiplied by 2;
TASK_ID_MULTED:
	DW	0
;==== ==== ====