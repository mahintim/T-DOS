;========================================;
;#	MAIN.S - T-DOS bootloader;	#;
;#	By Timur Salomakhin;		#;
;#	mahin.tim@gmail.com;		#;
;#	See README and LICENSE;		#;
;========================================;


;NASM directives;
[ORG $7C08]
[BITS 16]
[CPU 8086]
;==== ==== ====


;Constants;
TFS_VERSION	EQU	$7C02
TFS_SECTORS	EQU	$7C04
DISK_BUF	EQU	$600
TFS_NAME_SIZE	EQU	8
TFS_ENTRY_SIZE	EQU	16
SECTOR_SIZE	EQU	512
MIN_MEM_KB	EQU	64
DATA_TAB	EQU	$800
KERNEL		EQU	$900
TOO_FEW_MEM_ERR	EQU	'00'
NOT_FOUND_ERR	EQU	'01'
DISK_ERR	EQU	'02'
BAD_FS_ERR	EQU	'03'
;==== ==== ====


;Bootloader;
;IN:
;	DL - boot device number;
;OUT:
;	[$800-?] - kernel file;
;	PC - 0:$800;
;	AX - cylinders number;
;	BH - sectors number;
;	BL - heads number;
;	DL - boot device number;
;	BP - version of TFS;
;	SI:DI - number of sectors;
BOOT:
	;Setting segment registers and stack;
	cli
	xor	ax, ax
        mov	ds, ax
        mov	es, ax
        mov	ss, ax
        mov	sp, $7C00
        sti
	;====

	mov	ax, 2
	int	$10

	cld ;Direction is always zero;

	mov	[DRIVE_NUM], dl

	;Checking that there's enough RAM for DOS;
	int	$12
	cmp	ax, MIN_MEM_KB
	jge	BOOT_CNT
	;====

	mov	ax, TOO_FEW_MEM_ERR
	jmp	ERROR

BOOT_CNT:
	;Reseting boot disk (for some buggy BIOSes);
	xor	ax, ax
	int	$13
	;====

	;Reading disk's logical geometry;
	mov	ah, 8
	mov	si, DISK_BUF
	int	$13
	;====

	;Extracting number of sectors and storing it;
	mov	ax, cx
	and	al, $3F
	mov	[SECTORS], al
	;====

	;Extractng number of cylinders and storing it;
	mov	ax, cx
	and	al, $0C0
	mov	cl, 6
	shr	al, cl
	mov	bh, al
	mov	bl, ah
	inc	bx
	mov	[CYLINDERS], bx
	;====

	;Extracting number of heads;
	inc	dh
	mov	[HEADS], dh
	;====

	;Loading root directory's sector;
	xor	dx, dx
	mov	ax, 1
	call	LOAD_SECTOR
	;====

FIND_FILE:
	mov	di, DISK_BUF+1 ;DI is used as disk buffer's pointer;
	mov	dx, 31         ;DX is used as counter fot loop;

FIND_FILE_LP:
	;Decrease entry counter by 1 and check for end of loop;
	dec	dx
	test	dx, dx
	jz	FIND_FILE_ERR
	;====

	mov	cx, TFS_NAME_SIZE/2 ;CX is used as compare loop counter;
	xor	bh, bh              ;BH is used as not-EQUal flag;
	mov	si, KERNEL_FNAME

	push	di
	
FIND_FILE_CMP:	
	cmpsw
	jne	FIND_FILE_CONT2

FIND_FILE_CONT:
	loop	FIND_FILE_CMP

	pop	di

	;If not-equal flag == 0 then file found;
	cmp	bh, 0
	je	FIND_FILE_END
	;====

	;Else skipping 8 bytes of entry and continuing loop;
	add	di, 16
	jmp	FIND_FILE_LP
	;====

FIND_FILE_ERR:
	mov	ax, NOT_FOUND_ERR
	jmp	ERROR

FIND_FILE_CONT2:
	;Setting not-equal flag;
	inc	bh
	jmp	FIND_FILE_CONT
	;====

FIND_FILE_END:
	mov	ax, [di+8]
	mov	dx, [di+10]

;Loading kernel's file;
LOAD_KERNEL:
	;Setting ES to kernel's segment;
	mov	bx, KERNEL/16
	mov	es, bx
	;====

	xor	di, di ;DI is used as destination (kernel's segment);
	mov	si, DISK_BUF+1

LOAD_KERNEL_LP:
	call	LOAD_SECTOR

	;Checking that sector contains file data signature;
	cmp	byte [DISK_BUF], '&'
	jne	LOAD_KERNEL_ERR
	;====

	;Reading next sector's address;
	mov	ax, [DISK_BUF+SECTOR_SIZE-4]
	mov	dx, [DISK_BUF+SECTOR_SIZE-2]
	;====
	
	mov	cx, SECTOR_SIZE-5
	mov	si, DISK_BUF+1

	push	ax

LOAD_KERNEL_LP2:
	movsb
	loop	LOAD_KERNEL_LP2

LOAD_KERNEL_LP_END:

	pop	ax

	;If next sector == 0 then end of reading;
	test	ax, ax
	jnz	LOAD_KERNEL_CONT
	test	dx, dx
	jz	RUN_KERNEL
	;====

LOAD_KERNEL_CONT:
	jmp	LOAD_KERNEL_LP

LOAD_KERNEL_ERR:
	mov	ax, BAD_FS_ERR
	jmp	ERROR

RUN_KERNEL:
	mov	ax, [CYLINDERS]
	mov	bh, [SECTORS]
	mov	bl, [HEADS]
	mov	dl, [DRIVE_NUM]

	mov	bp, [TFS_VERSION]
	mov	di, [TFS_SECTORS]
	mov	si, [TFS_SECTORS+2]
	jmp	0:KERNEL
;==== ==== ====


;ERROR - subprogram;
;Print error message and reload PC after pressing any key;
;IN:
;	AX = error code in 2-ASCII characters;
ERROR:
	mov	[ERROR_CODE], ax
	mov	si, ERROR_MSG
	mov	ah, $0E

ERROR_LP:
	lodsb
	cmp	al, 0
	je	ERROR_END

	int	$10
	jmp	ERROR_LP

ERROR_END:
	hlt
;==== ==== ====


;LOAD_SECTOR - subprogram;
;Load 512-byte sector from disk;
;IN:
;	DX:AX - LBA of sector to read;
;OUT:
;	[ES:BX...ES:BX+512] - readed sector;
LOAD_SECTOR:
	;Storing registers' value;
	push	bx
	push	cx
	push	si
	push	di
	push	es
	;====

	mov	bx, 0
	mov	es, bx

	;Address of sector is saved in SI:DI;
	mov	di, ax
	mov	si, dx
	;====

	;tmp = heads * sectors; BX = tmp; [SS:SP+2] = tmp;
	mov	bl, [SECTORS]
	mov	al, [HEADS]
	mul	bl
	mov	bx, ax
	;====

	;cylinder = LBA / tmp;
	mov	ax, di
	mov	dx, si
	div	bx
	mov	[CYLINDER], ax
	;====

	;tmp2 = LBA / sectors; AX = tmp2;
	mov	ax, di
	mov	dx, si
	mov	bl, [SECTORS]
	xor	bh, bh
	div	bx
	;xor	ah, ah
	;====

	;head = tmp2 % heads;
	mov	bl, [HEADS]
	div	bl
	mov	[HEAD], ah
	;====

	;sector = LBA % sectors + 1;
	mov	ax, di
	mov	dx, si
	mov	bl, [SECTORS]
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
	mov	ax, [CYLINDER]
	and	ax, $0C0
	or	cx, ax
	;====

	mov	di, 5 ;DX used is attempts counter;

LOAD_SECTOR_LP:
	;Check that there's another attempt to try;
	inc	di
	test	dx, dx
	je	LOAD_SECTOR_FATAL_ERR
	;====

	;Reading sector;	
	mov	dh, [HEAD]
	mov	dl, [DRIVE_NUM]
	mov	bx, DISK_BUF
	mov	ah, 2
	mov	al, 1
	int	$13
	jnc	LOAD_SECTOR_END
	;====

LOAD_SECTOR_ERR:
	;Reseting disk controller;
	xor	ax, ax
	int	$13
	jmp	LOAD_SECTOR_LP
	;====

LOAD_SECTOR_END:
	;Loading registers' value;
	pop	es
	pop	di
	pop	si
	pop	cx
	pop	bx
	;====

	ret

LOAD_SECTOR_FATAL_ERR:
	mov	ax, DISK_ERR
	jmp	ERROR
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
KERNEL_FNAME:
	DB	'KERNEL.X'
ERROR_MSG:
	DB	'Error code: '
ERROR_CODE:
	DB	'00', 0
;==== ==== ====
