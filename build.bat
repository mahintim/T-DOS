rem #===============================================#
rem #	makefile - build script for Windows; 	    #
rem #	By Timur Salomakhin;			    #
rem #	mahin.tim@gmail.com;			    #
rem #	See README and LICENSE;			    #
rem #===============================================#

nasm BOOT\MAIN.S -o BIN\BOOT.B
ndisasm BIN\BOOT.B -b16 -o0x7C08 > DISASM\BOOT.S
python3 py\mkfs_tfs.py BIN\DISK.B BIN\BOOT.B 2048 1

nasm KERNEL/MAIN.S -Xgnu -o MOUNT/KERNEL.X
ndisasm MOUNT/KERNEL.X -b16 -o0x0800 > DISASM/KERNEL.S

python3 py/mkfs_tfs.py BIN/DISK.B BIN/BOOT.B 2048 1

qemu-system-i386.exe BIN/DISK.B