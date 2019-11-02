;========================================;
;#	MAIN.S - T-DOS kernel;		#;
;#	By Timur Salomakhin;		#;
;#	mahin.tim@gmail.com;		#;
;#	See README and LICENSE;		#;
;========================================;

[BITS 16]
[CPU 8086]
[ORG $800]

KERNEL_START:
	mov	ax, $0E45
	int	$10

KERNEL_END:
	hlt