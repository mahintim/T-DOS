;========================================;
;#	IO.S - Input/Output service;	#;
;#	By Timur Salomakhin;		#;
;#	mahin.tim@gmail.com;		#;
;#	See README and LICENSE;		#;
;========================================;

;Constants;
DISK_BUF	EQU	$600
;==== ==== ====


;Open file/directory from disk;
FILE_OPEN:
	ret
;==== ==== ====


;LOAD_SECTOR - subprogram;
;Load 512-byte sector from disk;
;IN:
;	DX:AX - LBA of sector to read;
;OUT:
;	[ES:BX...ES:BX+512] - read sector;
LOAD_SECTOR:
	mov	bx, 0
	mov	es, bx

	;Address of sector is saved in SI:DI;
	mov	di, ax
	mov	si, dx
	;====

	;tmp = heads * sectors; BX = tmp;
	mov	bl, [cs:SECTORS]
	mov	al, [cs:HEADS]
	mul	bl
	mov	bx, ax
	;====

	;cylinder = LBA / tmp;
	mov	ax, di
	mov	dx, si
	div	bx
	mov	[cs:CYLINDER], ax
	;====

	;tmp2 = LBA / sectors; AX = tmp2;
	mov	ax, di
	mov	dx, si
	mov	bl, [cs:SECTORS]
	xor	bh, bh
	div	bx
	;====

	;head = tmp2 % heads;
	mov	bl, [cs:HEADS]
	div	bl
	mov	[cs:HEAD], ah
	;====

	;sector = LBA % sectors + 1;
	mov	ax, di
	mov	dx, si
	mov	bl, [cs:SECTORS]
	mov	bh, 0
	div	bx
	inc	dx
	;====

	;Preparing data for BIOS call;
	;Now DX = sector; [CYLINDER] = cylinder; [HEAD] = head;
	;Cylinder and sector must be stored in CX using this format:
	; Part of register:           CH            |          CL
	; Bits of register: |15|14|13|12|11|10|09|08|07|06|05|04|03|02|01|00|
	; Bits of cylinder: | 7| 6| 5| 4| 3| 2| 1| 0| 9| 8|- |- |- |- |- |- |
	; Bits of sector:   |- |- |- |- |- |- |- |- |- |- | 5| 4| 3| 2| 1| 0|
	;Formula of translation data to CX:
	; CH = cylinder & $0FF;
	; CL = (cylinder & $0C0) | sector;
	mov	cx, dx
	mov	ax, [cs:CYLINDER]
	and	ax, $0C0
	or	cx, ax
	;====

	mov	di, 5 ;DX used is attempts counter;

.LP:
	;Check that there's another attempt to try;
	inc	di
	test	dx, dx
	je	.FATAL_ERR
	;====

	;Reading sector;	
	mov	dh, [cs:HEAD]
	mov	dl, [cs:DRIVE_NUM]
	mov	bx, DISK_BUF
	xor	ax, ax
	mov	es, ax
	mov	ah, 2
	mov	al, 1
	int	$13

	jnc	.END
	;====

.ERR:
	;Reseting disk controller;
	xor	ax, ax
	int	$13
	jmp	.LP
	;====

.END:
	clc
	ret

.FATAL_ERR:
	stc
	mov	ah, HARD_ERR
	ret
;==== ==== ====


;Variable data;
CYLINDER:
	DW	0
HEAD:
	DW	0
DRIVE_NUM:
	DB	0
CYLINDERS:
	DW	0
SECTORS:
	DB	0
HEADS:
	DB	0
TFS_VERSION:
	DW	0
TFS_SECTORS:
	DW	0
;==== ==== ====