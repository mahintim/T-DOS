#===============================================#
#	makefile - build script for *nix 	#
#	By Timur Salomakhin;			#
#	mahin.tim@gmail.com;			#
#	See README and LICENSE;			#
#===============================================#


all: BIN/DISK.B MOUNT/KERNEL.X
	python3 py/mnt_tfs.py -d BIN/DISK.B MOUNT

BIN/BOOT.B: BOOT/MAIN.S
	nasm BOOT/MAIN.S -o BIN/BOOT.B
	ndisasm BIN/BOOT.B -b16 -o0x7C08 > DISASM/BOOT.S

MOUNT/KERNEL.X: KERNEL/MAIN.S KERNEL/ERRORS.S KERNEL/TASK.S
	nasm KERNEL/MAIN.S -Xgnu -o MOUNT/KERNEL.X
	ndisasm MOUNT/KERNEL.X -b16 -o0x0900 > DISASM/KERNEL.S

BIN/DISK.B: BIN/BOOT.B
	python3 py/mkfs_tfs.py BIN/DISK.B BIN/BOOT.B 2048 1

clean:
	rm MOUNT/KERNEL.X BIN/BOOT.B BIN/DISK.B

run: all
	qemu-system-i386 BIN/DISK.B