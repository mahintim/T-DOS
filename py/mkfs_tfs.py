#!/usr/bin/python3

""" 
#===========================================#
#   mkfs_tfs.py - create TFS disk image.    #
#	By Timur Salomakhin;	                #
#	mahin.tim@gmail.com;                    #
#	See README and LICENSE;                 #
#===========================================#
"""

import struct
import argparse

parser = argparse.ArgumentParser()
parser.add_argument("disk_bin", help="path to disk binary file.")
parser.add_argument("boot_bin", help="path to boot binary image.")
parser.add_argument("sectors", help="number of sectors on disk.")
parser.add_argument("version", help="version of TFS. Use version from 'readme.md'.")
args = parser.parse_args()

disk_bin = open(args.disk_bin, "wb")
boot_bin = open(args.boot_bin, "rb")
sectors = int(args.sectors)
if sectors >= 0xFFFFFFFF or sectors <= 1:
    ValueError("Invalid sectors num.")
    
version = int(args.version)
if version >= 0xFFFF or version <= 0:
    ValueError("Invalid version.")

buf = boot_bin.read(510)
buf = bytes(list(list(buf) + [b'\0'[0]] * (510 - len(buf))))

disk_bin.write(struct.pack("<2sHI502sH", bytes([0xEB, 0x06]), version, sectors, buf, 0xAA55))

disk_bin.write(b'>')
for i in range(sectors * 512 - 1):
    disk_bin.write(b'\0')

print(str(sectors * 512) + " bytes wrote.")
