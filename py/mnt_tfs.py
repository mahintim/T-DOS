#!/usr/bin/python3

""" 
#===========================================#
#   mnt_tfs.py - mount/dismount TFS disk.   #
#	By Timur Salomakhin;	                #
#	mahin.tim@gmail.com;                    #
#	See README and LICENSE;                 #
#===========================================#
"""


import os
import struct
import shutil
import argparse
import sys


class Disk:
    SECTOR_SIZE = 512

    def __init__(self, bin_file):
        self.bin_file = bin_file
        self.bin_file.seek(2)
        self.version, self.sectors = struct.unpack("<HI", bin_file.read(6))
        self.mnt_point_stat = None

    def check_sector(self, sect: int):
        """ Check that sector's (`sect`) code is valid. """
        if sect >= self.sectors or sect < 0:
            raise ValueError("Sector '" + str(sect) + "' is unavailabel.")
        else:
            return sect

    def seek_to_sector(self, sect: int):
        """ Move binary file pointer (`self.bin_file`) to `sect`. """
        self.bin_file.seek(self.check_sector(sect) * Disk.SECTOR_SIZE)

    def load_sector(self, sect: int):
        """ Load sector with code `sect`. """
        self.seek_to_sector(sect)
        return self.bin_file.read(Disk.SECTOR_SIZE)

    def store_sector(self, sect: int, data):
        """ Store `data` byte array at sector with adress `sect` """
        self.seek_to_sector(sect)
        self.bin_file.write(bytes(data))
        self.bin_file.flush()

    def mount(self, mount_point_path: str):
        """ Mounting TFS disk, load all files and directories from `self.bin_file` to `mount_point_path'. """
        Entry(self).mount(mount_point_path)

    def dismount(self, mount_point_path: str):
        """ Dismounting TFS disk, moving all files from `mount_point_path` to `self.bin_file`. """
        self.mnt_point_stat = os.stat(mount_point_path)
        Entry(self).dismount(mount_point_path)

    def find_sector(self):
        """ Find free sector on disk. """
        for i in range(1, self.sectors):
            self.seek_to_sector(i)
            if self.bin_file.read(1)[0] == b'\0'[0]:
                return i

        raise IndexError("Cannot find free sector on disk.")


class Entry:
    NAME_SIZE = 8
    MAX_SIZE = 0xFFFFFFFF
    SIZE = struct.calcsize("<8sII")

    def __init__(self, disk: Disk, name: bytes = b"", sector: int = 1, size: int = 0xFFFFFFFF, parent_dir=None,
                 exists_on_disk: bool = True):
        self.disk = disk
        self.name = Entry.__check_name(name)
        self.sector = self.disk.check_sector(sector)
        self.size = Entry.__check_size(size)
        self.parent_dir = parent_dir
        self.exists_on_disk = exists_on_disk

    @staticmethod
    def __check_name(name: bytes):
        """ Check that name is availabel in TFS. """
        if len(name) > Entry.NAME_SIZE:
            raise ValueError("Too long name '" + str(name) + "'.")

        allowed = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-\0"

        for c in name:
            if not (c in allowed):
                raise ValueError("Found deprecated character '" + str(c) + "' in name '" + str(name) + "'.")

        return name.decode("utf-8").rstrip("\0")

    @staticmethod
    def __check_size(size: int):
        """ Check that size of entry is availabel in TFS. """
        if size > Entry.MAX_SIZE or size < 0:
            raise ValueError("Size '" + str(size) + "' is too small or too big.")
        else:
            return size

    @staticmethod
    def from_bytes(parent_dir, data: bytes):
        """ Convert raw bytes from `data` to `Entry` object. """
        tup = struct.unpack("<8sII", data)
        return Entry(parent_dir.entry.disk, tup[0], tup[1], tup[2], parent_dir)

    def to_bytes(self):
        """ Convert `self` to raw bytes. """
        return struct.pack("<8sII", bytes(self.name, "utf-8"), self.sector, self.size)

    def mount(self, mount_point_path: str):
        """ Mounting `self` to `mount_point_path`. """
        if self.size == 0xFFFFFFFF:
            Directory(self).mount(mount_point_path)
        else:
            File(self).mount(mount_point_path)

    def dismount(self, mount_point_path: str):
        """ Dismount `self` from `mount_point_path` to disk. """
        if self.size == 0xFFFFFFFF:
            Directory(self).dismount(mount_point_path)
        else:
            File(self).dismount(mount_point_path)

    def delete(self):
        """ Delete entry from disk. """
        self.disk.seek_to_sector(self.parent_dir.entry.sector)
        self.parent_dir.entries[self.parent_dir.entries.index(self)].name = " "

        if self.size == 0xFFFFFFFF:
            Directory(self).delete_data()
        else:
            File(self).delete_data()

    def create(self, fs_file_path: str):
        """ Create entry from `fs_file_path` on disk. """
        if os.path.isdir(fs_file_path):
            Directory(self, parse=False).create(fs_file_path)
        else:
            File(self).create(fs_file_path)


class Directory:
    MAX_ENTRIES = 31

    def __init__(self, entry: Entry, parse: bool = True):
        self.entry = entry
        self.entry.size = 0xFFFFFFFF
        self.entries = []

        if not parse:
            return
        else:
            self.entry.disk.seek_to_sector(self.entry.sector)
            if self.entry.disk.bin_file.read(1)[0] != b'>'[0] or self.entry.size != 0xFFFFFFFF:
                raise ValueError("Entry '" + self.entry.name + "' is not directory.")

            for i in range(0, Directory.MAX_ENTRIES):
                raw_data = self.entry.disk.bin_file.read(Entry.SIZE)
                if (raw_data[0] == b'\0'[0]) or (raw_data[0] == b' '[0]):
                    continue

                self.entries.append(Entry.from_bytes(self, raw_data))

    def mount(self, mount_point_path: str):
        """ Mount `self` to `mount_point_path` """
        os.mkdir(mount_point_path + self.entry.name)

        for e in self.entries:
            e.mount(mount_point_path + self.entry.name + "/")

    def dismount(self, mount_point_path: str):
        """ Dismount `self` from `mount_point_path` to disk. """
        if not os.path.exists(mount_point_path + self.entry.name):
            self.entry.delete()
        else:
            for tfs_ent in self.entries:
                tfs_ent.dismount(mount_point_path + self.entry.name + "/")

            fs_lists = os.listdir(mount_point_path + self.entry.name)

            for fs_ent in fs_lists:
                found = False

                for tfs_ent in self.entries:
                    if fs_ent == tfs_ent.name:
                        found = True

                if not found:
                    try:
                        e = Entry(self.entry.disk, name=fs_ent.encode("utf-8"), size=0)
                        e.create(mount_point_path + self.entry.name + "/" + fs_ent)
                        self.entries.append(e)
                    except ValueError as v:
                        print(v)
                        print("Skipping file '" + fs_ent + "'.")
                        continue

            self.entry.disk.store_sector(self.entry.sector, self.to_bytes())

    def delete_data(self):
        """ Delete directory's """
        for e in self.entries:
            e.delete()

        self.entry.disk.seek_to_sector(self.entry.sector)
        self.entry.disk.bin_file.write(b'\0')

    def to_bytes(self):
        buf = [b'>'[0]]
        for e in self.entries:
            buf += e.to_bytes()

        buf += [b'\0'[0]] * (Disk.SECTOR_SIZE - len(buf))
        return buf

    def create(self, fs_file_path: str):
        print("crdir")
        fs_lst = os.listdir(fs_file_path)
        for fs_ent in fs_lst:
            try:
                e = Entry(self.entry.disk, fs_ent.encode("utf-8"), parent_dir=self)
                e.create(fs_file_path + "/" + fs_ent)
                self.entries.append(e)
            except ValueError:
                print("Skipping file '" + fs_ent + "'.")
                continue

        self.entry.sector = self.entry.disk.find_sector()
        self.entry.disk.store_sector(self.entry.sector, self.to_bytes())


class File:
    def __init__(self, entry: Entry):
        self.entry = entry

    def mount(self, mount_point_path: str):
        f = open(mount_point_path + self.entry.name, "wb")

        next_sector = self.entry.sector
        bytes_at_last_sector = self.entry.size % (Disk.SECTOR_SIZE - 5)
        if bytes_at_last_sector == 0:
            bytes_at_last_sector = Disk.SECTOR_SIZE - 5

        while True:
            buf = self.entry.disk.load_sector(next_sector)
            if buf[0] != b'&'[0]:
                raise ValueError("Sector '" + str(next_sector) + "' contains status byte '" + str(buf[0]) + "' but "
                                                                                                            "waiting "
                                                                                                            "for '&'")

            tup = struct.unpack("<I", buf[Disk.SECTOR_SIZE - 4:Disk.SECTOR_SIZE])
            if tup[0] == 0:
                f.write(buf[1:bytes_at_last_sector + 1])
                break
            else:
                f.write(buf[1:Disk.SECTOR_SIZE - 4])
                next_sector = tup[0]

        f.close()

    def dismount(self, mount_point_path: str):
        if not os.path.exists(mount_point_path + self.entry.name):
            self.entry.delete()
        else:
            self.delete_data()
            self.create(mount_point_path + self.entry.name)

    def delete_data(self):
        next_sector = self.entry.sector
        while True:
            buf = list(self.entry.disk.load_sector(next_sector))
            buf[0] = b'\0'[0]
            tup = struct.unpack("<I", bytes(buf[Disk.SECTOR_SIZE - 4:Disk.SECTOR_SIZE]))
            self.entry.disk.store_sector(next_sector, buf)
            if tup[0] == 0:
                break
            else:
                next_sector = tup[0]

    def create(self, fs_file_path: str):
        fs_file = open(fs_file_path, "rb")

        self.entry.size = os.stat(fs_file_path).st_size
        next_sector = self.entry.disk.find_sector()
        self.entry.sector = next_sector
        bytes_to_transfer = self.entry.size

        while True:
            cur_sector = next_sector
            buf = fs_file.read(Disk.SECTOR_SIZE - 5)
            self.entry.disk.seek_to_sector(cur_sector)
            self.entry.disk.bin_file.write(b'&')

            if bytes_to_transfer <= (Disk.SECTOR_SIZE - 5):
                next_sector = 0
            else:
                next_sector = self.entry.disk.find_sector()

            self.entry.disk.store_sector(cur_sector, list([b'&'[0]]) + list(buf) + list(bytes(Disk.SECTOR_SIZE - 5 - len(buf))) + list(struct.pack("<I", next_sector)))
            bytes_to_transfer -= Disk.SECTOR_SIZE - 5

            if next_sector == 0:
                break


parser = argparse.ArgumentParser()
parser.add_argument("disk_bin", help="path to disk binary file.")
parser.add_argument("mount_point", help="path mount point.")
parser.add_argument("-d", help="dismounting flag.", action="store_true")
args = parser.parse_args()

disk_file = open(args.disk_bin, "r+b")
disk = Disk(disk_file)

if args.d:
    disk.dismount(args.mount_point)
else:
    if os.path.exists(args.mount_point):
        shutil.rmtree(args.mount_point)
    disk.mount(args.mount_point)
