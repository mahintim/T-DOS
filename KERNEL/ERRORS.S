;========================================;
;#	MAIN.S - List of T-DOS errors;	#;
;#	By Timur Salomakhin;		#;
;#	mahin.tim@gmail.com;		#;
;#	See README and LICENSE;		#;
;========================================;

;No error (usually means success);
NO_ERR		EQU	0
;Hardware IO error;
HARD_ERR	EQU	1
;No free segments to allocate error;
NO_SEGS_ERR	EQU	2
;Invalid segment;
SEG_INV_ERR     EQU     3